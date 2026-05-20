# intel-platform — plan działania

## Cel projektu (jedno zdanie)

Zweryfikować bazę 15 000 leadów z Jitbita (kto żyje, kto nie żyje), wzbogacić o sygnały biznesowe i regularnie monitorować pod kątem okazji sprzedażowych.

## Zasada nadrzędna

**MVP-first. Każda faza musi mieć działający output zanim startuje następna.**
Nic nie budujemy "na zapas". Architekturalne decyzje odraczamy do momentu kiedy są naprawdę potrzebne.

---

## Stan startowy (2026-05-20)

✅ Infrastruktura gotowa:
- LXC `intel-monitor` na Proxmox (10.1.1.50, Debian 13 Trixie)
- Python 3.13.5, SSH klucz, klient MariaDB
- Baza `vivcom_intel` na Zenbox s49.zenbox.pl (MariaDB 10.6.21, pusta)
- Publiczny repo: github.com/rwojcikviv/intel-platform

---

## Faza 1 — Schemat + import z Jitbita

**Cel:** `intel_leads` zawiera 15k rekordów z basic info (firma, NIP, URL, email, kraj).

**Kroki:**
1. Apply migracji `sql/migrations/001_initial_schema.sql` na bazę Zenbox
2. Weryfikacja: `SHOW TABLES` zwraca 7 tabel, `SELECT * FROM intel_business_units` zwraca 2 wiersze
3. Skrypt `scripts/import_jitbit.py`:
   - Podłącza się do MSSQL Jitbita przez `pyodbc`
   - SELECT z odpowiedniej tabeli kontaktów Jitbita (do ustalenia jaka)
   - Mapowanie kolumn Jitbit → `intel_leads`
   - INSERT batch po 500 rekordów (transakcyjnie)
   - Loguje statystyki: ile importowanych, ile pominiętych, jakie błędy

**Output:** `SELECT COUNT(*) FROM intel_leads` ≈ 15000

**Decyzje do podjęcia w trakcie:**
- Jaka tabela Jitbita jest źródłem? (do potwierdzenia po inspekcji bazy)
- Czy importujemy wszystkie kraje czy tylko PL na start?
- Domyślny `business_unit` przy imporcie? (zakładam VIV, można zmienić bulk update)

---

## Faza 2 — Walidacja techniczna

**Cel:** Dla każdego leada wiemy czy strona WWW i email są technicznie poprawne.

**Kroki:**
1. Skrypt `scripts/verify_technical.py`:
   - Dla każdego leada z `intel_leads`:
     - Jeśli `website_url`: HEAD request → status code, redirect chain, parking page detection
     - Jeśli `primary_email`: format check + opcjonalnie MX record lookup
   - Zapisuje wynik do `intel_verifications` z `verifier='url_liveness'` / `'email_format'`
   - Update `intel_leads.last_verified_at`

**Output:** Każdy lead ma przynajmniej jeden wpis w `intel_verifications`. Można policzyć:
- Ile URL-i odpowiada 200 OK
- Ile to martwe domeny (NXDOMAIN, parking pages)
- Ile maili ma poprawny format

**Czas:** dla 15k leadów × 1 HEAD request = ~30-60 min (asyncio, 50 concurrent workers)

---

## Faza 3 — Walidacja przez polskie rejestry

**Cel:** Dla polskich leadów wiemy czy firma jest zarejestrowana, aktywna, w jakiej branży (PKD).

**Kroki:**
1. `intel/verifiers/biala_lista.py` — Biała Lista VAT (bezpłatne API MF, po NIP)
2. `intel/verifiers/gus_regon.py` — GUS REGON (bezpłatne API, po NIP daje PKD)
3. `intel/verifiers/ceidg.py` — CEIDG (bezpłatne API, dla jednoosobowych)
4. `intel/verifiers/krs.py` — KRS (bezpłatne API, dla spółek)
5. Skrypt `scripts/verify_polish.py`:
   - Filter `intel_leads WHERE country_code='PL' AND nip IS NOT NULL`
   - Dla każdego: wywołanie odpowiednich rejestrów
   - Wyniki → `intel_verifications` per verifier
   - Klasyfikacja: PKD → mapping → `intel_lead_categories` (np. PKD 47.78.Z → dmuchance/inne)
   - Update `intel_leads.status` na podstawie agregacji wyników

**Output:** Dla polskich leadów: status `active` / `dormant` / `dead` w `intel_leads.status` + assignments do kategorii.

**Decyzje:**
- Co robić z leadami bez NIP? (próbować fuzzy match po nazwie? na razie pomijamy, oznaczamy `unverified`)
- Mapping PKD → kategorie wewnętrzne — wymaga ręcznej tabeli mapowania (kolejna migracja)

---

## Faza 4 — Pierwszy raport MVP

**Cel:** Dostajesz raport HTML/CSV: kto żyje, kto nie, co warto zrobić.

**Kroki:**
1. Skrypt `scripts/report_status.py`:
   - Query: leady aktywne / dormant / dead per kategoria / per kraj
   - Render Jinja2 → HTML (kolumny: nazwa, status, ostatnia weryfikacja, NIP, URL)
   - Eksport: HTML + CSV w `data/reports/raport_YYYY-MM-DD.html`
2. Manualnie wysyłasz raport handlowcom (email z załącznikiem albo upload na Drive)

**Output:** Działający raport. Możesz zacząć czyścić CRM (archiwizować martwe leady, dzwonić do żywych).

**To koniec MVP.** Po Fazie 4 masz wartość biznesową. Można żyć tylko z tym.

---

## Fazy 5+ (przyszłość — startujemy gdy MVP działa stabilnie)

Te fazy są pomysłami, nie zobowiązaniem. Decyzję o uruchomieniu każdej podejmiesz po Fazie 4, mając dane z MVP.

### Faza 5 — Ongoing monitoring (sygnały biznesowe)
- Migracja 002: tabele `intel_snapshots`, `intel_signals`
- Periodic fetch stron WWW aktywnych leadów (np. raz w miesiącu)
- Diff vs poprzedni snapshot → wykrywanie zmian
- LLM analyzer (Anthropic API) → klasyfikacja sygnałów (nowy event, expansion, redesign...)
- Output: weekly digest dla handlowców z hot/warm leadami

### Faza 6 — Pozostałe kategorie
- Karuzele/rodeo: ten sam pipeline, inne mapowania PKD, inne sygnały
- Budownictwo modułowe: business_unit `modular`, prawdopodobnie inne źródła leadów

### Faza 7 — Integracja z CRM
- Adapter do Krayina (gdy go wdrożysz) — push leadów i sygnałów przez REST API
- Custom fields w Krayin: `intel_status`, `last_signal_type`, `lead_temperature`

### Faza 8 — Rozszerzenie poza Polskę
- Verifiers dla DE (Unternehmensregister), FR (Pappers/Infogreffe), itd.
- Per kraj — osobny moduł, ten sam interfejs

### Faza 9 — Moduł konkurencji (side concern)
- Osobna lista (nie w `intel_leads`), inny prompt analyzera
- Cadence 2-tygodniowy
- Raport strategiczny dla Roberta, nie dla handlowców

---

## Zasady operacyjne

1. **Każda zmiana w schemacie = nowy plik migracji** (`002_xxx.sql`, `003_xxx.sql` itd.). Nigdy nie modyfikujemy starych.
2. **Sekrety tylko w `.env` na LXC.** Nigdy w repo.
3. **Każdy skrypt loguje do `logs/`.** Loguru z rotacją.
4. **Deploy na LXC = `git pull` + ewentualne `pip install` + ręczne odpalenie migracji.** Bez automatów na razie.
5. **Snapshot Proxmoxa przed każdą większą zmianą.** Rollback w sekundach.

---

## Co teraz robimy

Jesteśmy między Fazą 0 (setup, ✅ skończone) a Fazą 1.

**Następne konkretne kroki:**
1. Sklonowanie repo na LXC (`git clone` do `/opt/intel-platform`)
2. Utworzenie `.env` z credentials (kopia `.env.example` + uzupełnienie)
3. Instalacja zależności (`pip install -r requirements.txt` w venv)
4. Apply migracji 001 na Zenbox
5. Inspekcja Jitbit MSSQL — która tabela jest źródłem 15k kontaktów
6. Pisanie `scripts/import_jitbit.py`
