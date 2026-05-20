"""File-based connector — CSV/TSV/XLSX → intel_raw_leads staging.

Strategia:
- Czyta plik przez pandas (auto-detect format po rozszerzeniu)
- Normalizuje nazwy kolumn (kropki → underscore)
- Mapuje 1:1 na kolumny intel_raw_leads (przecięcie nazw)
- Kolumny w pliku BEZ odpowiednika w tabeli — loguje warning, pomija
- INSERT ... ON DUPLICATE KEY UPDATE po (source_id, source_external_id)
- Statystyki na koniec
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pandas as pd
import yaml
from loguru import logger
from sqlalchemy import text

from intel.db import get_engine, session_scope


@dataclass
class ImportStats:
    """Statystyki po imporcie."""
    total_rows: int = 0
    inserted: int = 0
    updated: int = 0
    skipped: int = 0
    failed: int = 0
    errors: list[str] = field(default_factory=list)

    def summary(self) -> str:
        return (
            f"Wiersze w pliku: {self.total_rows}\n"
            f"  Zapisanych nowych: {self.inserted}\n"
            f"  Zaktualizowanych: {self.updated}\n"
            f"  Pominiętych (brak external_id): {self.skipped}\n"
            f"  Z błędem: {self.failed}\n"
            f"  Łącznie błędów: {len(self.errors)}"
        )


class FileConnector:
    """Loads CSV/TSV/XLSX files into intel_raw_leads staging table.

    Configured via YAML — auto-maps file columns to table columns by name
    (after normalization: dots → underscores).
    """

    BATCH_SIZE = 100

    def __init__(self, config_path: str | Path) -> None:
        self.config_path = Path(config_path)
        with open(self.config_path, "r", encoding="utf-8") as f:
            self.config = yaml.safe_load(f)

        self.source_code: str = self.config["source"]
        self.external_id_field: str = self.config["external_id_field"]
        self.defaults: dict = self.config.get("defaults", {})
        self.auto_map: dict = self.config.get(
            "auto_map", {"enabled": True, "normalize": "dots_to_underscores"}
        )

        self._source_id: int | None = None
        self._table_columns: set[str] = set()

        logger.info(f"FileConnector załadowany z {self.config_path}")
        logger.info(f"  source: {self.source_code}")
        logger.info(f"  external_id_field: {self.external_id_field}")

    # ============= PUBLIC =============

    def import_file(
        self,
        file_path: str | Path,
        batch_id: str,
        dry_run: bool = False,
    ) -> ImportStats:
        """Main method: read file → map → upsert do intel_raw_leads."""
        file_path = Path(file_path)
        if not file_path.exists():
            raise FileNotFoundError(f"Plik nie istnieje: {file_path}")

        logger.info(f"=== Import: {file_path} ===")
        logger.info(f"Batch ID: {batch_id}")
        if dry_run:
            logger.warning("DRY RUN — nie wpisuję do bazy")

        # 1. Wczytaj
        df = self._read_file(file_path)
        logger.info(f"Wczytano {len(df)} wierszy, {len(df.columns)} kolumn")

        # 2. Normalizuj nazwy kolumn
        df = self._normalize_columns(df)

        # 3. Pobierz schema docelowej tabeli
        self._load_table_schema()

        # 4. Logging niezmapowanych
        file_cols = set(df.columns)
        unmapped = file_cols - self._table_columns
        if unmapped:
            logger.warning(
                f"Kolumny w pliku BEZ odpowiednika w intel_raw_leads "
                f"(zostaną pominięte): {sorted(unmapped)}"
            )
        import_cols = file_cols & self._table_columns
        logger.info(f"Kolumn do importu: {len(import_cols)}")

        # 5. Resolve source_id
        self._source_id = self._resolve_source_id()

        # 6. Batch upsert
        stats = ImportStats(total_rows=len(df))

        if dry_run:
            if len(df) > 0:
                preview = self._prepare_row(df.iloc[0], import_cols, batch_id)
                logger.info("Preview pierwszego wiersza (15 pól):")
                for k, v in list(preview.items())[:15]:
                    val_str = str(v)
                    if len(val_str) > 80:
                        val_str = val_str[:80] + "..."
                    logger.info(f"  {k}: {val_str}")
            return stats

        batch: list[dict] = []
        for idx, row in df.iterrows():
            try:
                prepared = self._prepare_row(row, import_cols, batch_id)
                if prepared.get("source_external_id") is None:
                    logger.warning(
                        f"Wiersz {idx}: brak '{self.external_id_field}', pomijam"
                    )
                    stats.skipped += 1
                    continue
                batch.append(prepared)
                if len(batch) >= self.BATCH_SIZE:
                    self._upsert_batch(batch, stats)
                    batch.clear()
            except Exception as e:
                msg = f"Wiersz {idx}: {e}"
                logger.error(msg)
                stats.failed += 1
                stats.errors.append(msg)

        if batch:
            self._upsert_batch(batch, stats)

        logger.success(f"Import zakończony.\n{stats.summary()}")
        return stats

    # ============= PRIVATE =============

    def _read_file(self, path: Path) -> pd.DataFrame:
        """Auto-detect format based on extension."""
        suffix = path.suffix.lower()
        if suffix in (".xlsx", ".xls"):
            return pd.read_excel(path)
        elif suffix == ".csv":
            return pd.read_csv(path)
        elif suffix == ".tsv":
            return pd.read_csv(path, sep="\t")
        else:
            raise ValueError(f"Nieobsługiwane rozszerzenie: {suffix}")

    def _normalize_columns(self, df: pd.DataFrame) -> pd.DataFrame:
        """Dots → underscores w nazwach kolumn."""
        if not self.auto_map.get("enabled"):
            return df
        normalize = self.auto_map.get("normalize", "dots_to_underscores")
        rename_map: dict[str, str] = {}
        for col in df.columns:
            new = col
            if "dots_to_underscores" in normalize:
                new = new.replace(".", "_")
            rename_map[col] = new
        return df.rename(columns=rename_map)

    def _load_table_schema(self) -> None:
        """Pobierz listę kolumn intel_raw_leads."""
        query = text("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = DATABASE()
              AND table_name = 'intel_raw_leads'
        """)
        with get_engine().connect() as conn:
            result = conn.execute(query)
            self._table_columns = {row[0] for row in result}
        logger.debug(f"Schema: {len(self._table_columns)} kolumn w intel_raw_leads")

    def _resolve_source_id(self) -> int:
        """SELECT id FROM intel_lead_sources WHERE code=:code."""
        query = text("SELECT id FROM intel_lead_sources WHERE code = :code")
        with get_engine().connect() as conn:
            row = conn.execute(query, {"code": self.source_code}).fetchone()
            if not row:
                raise ValueError(
                    f"Source '{self.source_code}' nie istnieje w intel_lead_sources. "
                    f"Dodaj go migracją SQL."
                )
            return int(row[0])

    def _prepare_row(
        self,
        row: pd.Series,
        import_cols: set[str],
        batch_id: str,
    ) -> dict[str, Any]:
        """Wyciągnij wartości, NaN → None, koercja typów."""
        prepared: dict[str, Any] = {
            "source_id": self._source_id,
            "import_batch_id": batch_id,
        }

        # Auto-mapped kolumny z pliku
        for col in import_cols:
            value = row.get(col)
            if pd.isna(value):
                prepared[col] = None
            elif isinstance(value, bool):
                prepared[col] = 1 if value else 0
            else:
                prepared[col] = value

        # external_id mapping (np. place_id → source_external_id)
        ext_id_value = row.get(self.external_id_field)
        if pd.isna(ext_id_value):
            prepared["source_external_id"] = None
        else:
            prepared["source_external_id"] = str(ext_id_value).strip()

        # Defaults z config (nie nadpisują istniejących)
        for k, v in self.defaults.items():
            if k not in prepared or prepared[k] is None:
                prepared[k] = v

        return prepared

    def _upsert_batch(self, batch: list[dict], stats: ImportStats) -> None:
        """INSERT ... ON DUPLICATE KEY UPDATE batchem.

        MariaDB rowcount convention:
          1 = INSERT (nowy wiersz)
          2 = UPDATE (istniał, zaktualizowany)
        """
        if not batch:
            return

        # Wszystkie kolumny które ustawiamy
        all_cols: set[str] = set()
        for row in batch:
            all_cols.update(row.keys())

        # Wymagane meta
        all_cols.add("source_id")
        all_cols.add("source_external_id")
        all_cols.add("import_batch_id")

        cols_list = sorted(all_cols)
        col_names = ", ".join(f"`{c}`" for c in cols_list)
        placeholders = ", ".join(f":{c}" for c in cols_list)

        # ON DUPLICATE: aktualizuj wszystko poza id i imported_at
        update_cols = [c for c in cols_list if c not in ("id", "imported_at")]
        update_clause = ", ".join(f"`{c}` = VALUES(`{c}`)" for c in update_cols)
        update_clause += ", `last_seen_at` = CURRENT_TIMESTAMP"

        sql = text(f"""
            INSERT INTO intel_raw_leads ({col_names})
            VALUES ({placeholders})
            ON DUPLICATE KEY UPDATE {update_clause}
        """)

        with session_scope() as session:
            for row in batch:
                # Dopełnij brakujące kolumny None'ami
                full_row = {c: row.get(c) for c in cols_list}
                try:
                    result = session.execute(sql, full_row)
                    if result.rowcount == 1:
                        stats.inserted += 1
                    elif result.rowcount == 2:
                        stats.updated += 1
                except Exception as e:
                    stats.failed += 1
                    stats.errors.append(f"Upsert error: {e}")
                    logger.error(f"Upsert: {e}")
                    