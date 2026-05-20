"""CLI: import pliku do intel_raw_leads.

Użycie:
    python -m scripts.import_file --source outscraper_gmaps \\
        --file data/Out-PL.xlsx \\
        --batch-id outscraper_2026-05-20_PL_eventowa

    python -m scripts.import_file --source outscraper_gmaps \\
        --file data/Out-PL.xlsx \\
        --batch-id outscraper_2026-05-20_PL_eventowa \\
        --dry-run
"""
from __future__ import annotations

import sys
from pathlib import Path

import click
from loguru import logger

from intel.connectors.file_connector import FileConnector


# Setup loguru — file rotation
LOG_DIR = Path("/opt/intel-platform/logs")
LOG_DIR.mkdir(parents=True, exist_ok=True)

logger.add(
    LOG_DIR / "import_{time:YYYY-MM-DD}.log",
    rotation="00:00",       # daily rotation
    retention="30 days",
    level="DEBUG",
    format="{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {message}",
)


@click.command()
@click.option(
    "--source", "-s",
    required=False,
    help="Nazwa source (resolve do configs/mappings/{source}.yaml). Alternatywa: --config",
)
@click.option(
    "--config", "-c",
    type=click.Path(exists=True),
    required=False,
    help="Pełna ścieżka do pliku config YAML (override dla --source)",
)
@click.option(
    "--file", "-f",
    type=click.Path(exists=True),
    required=True,
    help="Ścieżka do pliku CSV/TSV/XLSX",
)
@click.option(
    "--batch-id", "-b",
    required=True,
    help="Identyfikator batcha (np. outscraper_2026-05-20_PL_eventowa)",
)
@click.option(
    "--dry-run",
    is_flag=True,
    default=False,
    help="Pokaż co by się stało, nie wpisuj do bazy",
)
def main(
    source: str | None,
    config: str | None,
    file: str,
    batch_id: str,
    dry_run: bool,
) -> None:
    """Import pliku CSV/TSV/XLSX do intel_raw_leads."""
    # Resolve config path
    if config:
        config_path = Path(config)
    elif source:
        # Szukaj w configs/mappings/ względem korzenia projektu
        project_root = Path(__file__).resolve().parent.parent
        config_path = project_root / "configs" / "mappings" / f"{source}.yaml"
        if not config_path.exists():
            logger.error(f"Config nie istnieje: {config_path}")
            sys.exit(1)
    else:
        logger.error("Musisz podać --source lub --config")
        sys.exit(1)

    connector = FileConnector(config_path)
    stats = connector.import_file(
        file_path=file,
        batch_id=batch_id,
        dry_run=dry_run,
    )

    if stats.failed > 0:
        logger.warning(f"Zakończono z błędami: {stats.failed}")
        sys.exit(1)


if __name__ == "__main__":
    main()
    