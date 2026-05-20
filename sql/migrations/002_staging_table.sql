-- intel-platform — migration 002: staging table for raw lead data
-- Target: MariaDB 10.6+ (Zenbox vivcom_intel)
-- Pattern: staging table (intel_raw_leads) → walidacja → promocja do intel_leads (CRM)
-- Wszystkie 121 kolumn z Outscrapera + nasze meta (zarządzanie) + nasze enrichment (NIP, KRS, walidacja).

-- =====================================================
-- STAGING TABLE: intel_raw_leads
-- Brudnopis — surowe dane ze wszystkich źródeł.
-- Promowane do intel_leads dopiero po walidacji.
-- =====================================================
CREATE TABLE IF NOT EXISTS intel_raw_leads (
    id                              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    -- =====================================================
    -- META (zarządzanie wierszami — kto, skąd, kiedy)
    -- =====================================================
    source_id                       INT UNSIGNED NOT NULL COMMENT 'FK do intel_lead_sources (np. outscraper_gmaps)',
    import_batch_id                 VARCHAR(100) COMMENT 'np. outscraper_2026-05-20_PL_eventowa',
    source_external_id              VARCHAR(255) COMMENT 'place_id (Outscraper), ID z Jitbita itp.',
    imported_at                     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at                    DATETIME COMMENT 'Aktualizowane przy każdym re-imporcie tego place_id',
    updated_at                      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    -- =====================================================
    -- VALIDATION STATUS (nasz workflow walidacji)
    -- =====================================================
    validation_status               ENUM(
                                        'new',                  -- świeżo zaimportowany
                                        'in_progress',          -- walidacja w toku
                                        'validated_ok',         -- przeszedł, gotowy do promocji
                                        'validated_failed',     -- nie przeszedł
                                        'promoted',             -- już w intel_leads
                                        'rejected',             -- jawnie odrzucony
                                        'manual_review'         -- wymaga ręcznej decyzji
                                    ) NOT NULL DEFAULT 'new',
    validation_notes                TEXT COMMENT 'Komentarze z walidatorów',
    promoted_to_lead_id             BIGINT UNSIGNED COMMENT 'FK do intel_leads.id po promocji',
    promoted_at                     DATETIME,

    -- =====================================================
    -- ENRICHMENT (uzupełniane przez nasze walidatory)
    -- Outscraper tych pól nie zwraca dla polskich firm.
    -- =====================================================
    nip                             VARCHAR(20) COMMENT 'Numer NIP (10 cyfr), pobierany z GUS/CEIDG po fuzzy match',
    regon                           VARCHAR(20) COMMENT 'REGON (9 lub 14 cyfr)',
    krs                             VARCHAR(20) COMMENT 'Numer KRS dla spółek',
    pkd                             VARCHAR(20) COMMENT 'Główny kod PKD',
    legal_form                      VARCHAR(50) COMMENT 'spolka_z_o_o, jdg, spolka_jawna, fundacja itd.',
    vat_active                      TINYINT(1) COMMENT '1=aktywny, 0=wykreślony, NULL=nie sprawdzano (Biała Lista)',

    -- =====================================================
    -- OUTSCRAPER FIELDS (121 kolumn 1:1 z pliku)
    -- Kropki w oryginalnych nazwach zastąpione podkreślnikami.
    -- =====================================================
    
    -- Query i podstawowa identyfikacja
    query                           VARCHAR(500) COMMENT 'Outscraper: query który znalazł tego leada',
    name                            VARCHAR(500),
    name_for_emails                 VARCHAR(500),
    subtypes                        VARCHAR(500),
    category                        VARCHAR(200),
    type                            VARCHAR(200),

    -- Telefon główny + enrichment
    phone                           VARCHAR(50),
    phone_phones_enricher_carrier_name      VARCHAR(200),
    phone_phones_enricher_carrier_type      VARCHAR(50),

    -- Website + adres
    website                         VARCHAR(1000),
    address                         VARCHAR(500),
    street                          VARCHAR(255),
    city                            VARCHAR(200),
    county                          VARCHAR(200),
    state                           VARCHAR(200),
    state_code                      VARCHAR(20),
    postal_code                     VARCHAR(20),
    country                         VARCHAR(100),
    country_code                    CHAR(2),
    domain                          VARCHAR(255),

    -- Company-level info
    company_name                    VARCHAR(500),
    company_phone                   VARCHAR(50),
    company_phone_phones_enricher_carrier_name  VARCHAR(200),
    company_phone_phones_enricher_carrier_type  VARCHAR(50),
    company_phones                  TEXT COMMENT 'CSV-list lub JSON list',
    company_linkedin                VARCHAR(500),
    company_facebook                VARCHAR(500),
    company_instagram               VARCHAR(500),
    company_x                       VARCHAR(500),
    company_youtube                 VARCHAR(500),

    -- Contact person
    full_name                       VARCHAR(255),
    first_name                      VARCHAR(100),
    last_name                       VARCHAR(100),
    title                           VARCHAR(200),

    -- Email + walidacja
    email                           VARCHAR(255),
    email_emails_validator_status           VARCHAR(50)  COMMENT 'RECEIVING / RISKY / UNDELIVERABLE itp.',
    email_emails_validator_status_details   VARCHAR(255),

    -- Contact phone + enrichment
    contact_phone                   VARCHAR(50),
    contact_phone_phones_enricher_carrier_type  VARCHAR(50),
    contact_phone_phones_enricher_carrier_name  VARCHAR(200),
    contact_phones                  TEXT,

    -- Contact socials
    contact_linkedin                VARCHAR(500),
    contact_facebook                VARCHAR(500),
    contact_instagram               VARCHAR(500),
    contact_x                       VARCHAR(500),

    -- Website intelligence
    website_title                   VARCHAR(500),
    website_description             TEXT,
    website_generator               VARCHAR(255) COMMENT 'WordPress, Shopify, custom itp.',
    website_has_gtm                 TINYINT(1) COMMENT 'Google Tag Manager obecny',
    website_has_fb_pixel            TINYINT(1) COMMENT 'Facebook Pixel obecny',

    -- Skąd Outscraper wziął dane
    source                          VARCHAR(50) COMMENT 'Outscraper field: google_maps, places_api itp.',

    -- Geo
    latitude                        DECIMAL(11, 8),
    longitude                       DECIMAL(11, 8),
    h3                              VARCHAR(20) COMMENT 'H3 geospatial index',
    time_zone                       VARCHAR(50),
    plus_code                       VARCHAR(50),
    area_service                    TINYINT(1) COMMENT 'Firma działa w terenie (a nie w lokalu)',

    -- Reviews + ratings
    rating                          DECIMAL(3, 2),
    reviews                         INT UNSIGNED,
    reviews_link                    VARCHAR(1000),
    reviews_tags                    TEXT,
    reviews_per_score               TEXT COMMENT 'JSON: {"1":0,"2":0,"3":1,"4":7,"5":24}',
    reviews_per_score_1             INT UNSIGNED,
    reviews_per_score_2             INT UNSIGNED,
    reviews_per_score_3             INT UNSIGNED,
    reviews_per_score_4             INT UNSIGNED,
    reviews_per_score_5             INT UNSIGNED,

    -- Photos
    photos_count                    INT UNSIGNED,
    photo                           VARCHAR(1000),
    street_view                     VARCHAR(1000),
    logo                            VARCHAR(1000),

    -- Located in (np. centrum handlowe)
    located_in                      VARCHAR(500),
    located_google_id               VARCHAR(100),

    -- Business status + working hours (KLUCZOWE dla walidacji)
    business_status                 VARCHAR(50) COMMENT 'OPERATIONAL / CLOSED_TEMPORARILY / CLOSED_PERMANENTLY',
    working_hours                   TEXT,
    working_hours_csv_compatible    TEXT,
    other_hours                     TEXT,
    popular_times                   TEXT COMMENT 'JSON object',
    typical_time_spent              VARCHAR(100),

    -- Range / prices
    `range`                         VARCHAR(50) COMMENT '$ / $$ / $$$ — backticks bo range jest słowem kluczowym',
    prices                          TEXT,
    reservation_links               TEXT,
    booking_appointment_link        VARCHAR(1000),
    menu_link                       VARCHAR(1000),
    order_links                     TEXT,

    -- Description / about
    about                           TEXT,
    description                     TEXT,
    posts                           TEXT COMMENT 'JSON z postami Google Business Profile',

    -- Verification + owner
    verified                        TINYINT(1) COMMENT 'Czy właściciel claimował listing',
    owner_id                        VARCHAR(50),
    owner_title                     VARCHAR(500),
    owner_link                      VARCHAR(1000),

    -- Linki do Google Maps
    location_link                   VARCHAR(1000),
    location_reviews_link           VARCHAR(1000),

    -- Identyfikatory Google
    place_id                        VARCHAR(100) COMMENT 'Stabilny ID Google Maps (głównie używamy w source_external_id)',
    google_id                       VARCHAR(100),
    cid                             VARCHAR(50) COMMENT 'BIGINT jako VARCHAR (mieści 19+ cyfr)',
    kgmid                           VARCHAR(50),
    reviews_id                      VARCHAR(50),

    -- Company insights (LinkedIn-based enrichment)
    company_insights_country                VARCHAR(100),
    company_insights_description            TEXT,
    company_insights_employees              INT UNSIGNED,
    company_insights_founded_year           SMALLINT UNSIGNED,
    company_insights_industry               VARCHAR(200),
    company_insights_is_public              TINYINT(1),
    company_insights_linkedin_bio           TEXT,
    company_insights_linkedin_company_page  VARCHAR(500),
    company_insights_name                   VARCHAR(500),
    company_insights_revenue                BIGINT UNSIGNED COMMENT 'W USD',
    company_insights_timezone               VARCHAR(50),
    company_insights_address                VARCHAR(500),
    company_insights_city                   VARCHAR(200),
    company_insights_facebook_company_page  VARCHAR(500),
    company_insights_state                  VARCHAR(200),
    company_insights_zip                    VARCHAR(20),
    company_insights_twitter_handle         VARCHAR(100),
    company_insights_phone                  VARCHAR(50),
    company_insights_phone_phones_enricher_carrier_name  VARCHAR(200),
    company_insights_phone_phones_enricher_carrier_type  VARCHAR(50),
    company_insights_total_money_raised     BIGINT UNSIGNED,

    -- Chain info
    chain_info_chain                VARCHAR(255),

    -- =====================================================
    -- KEYS
    -- =====================================================
    PRIMARY KEY (id),
    UNIQUE KEY uq_raw_source_external (source_id, source_external_id) COMMENT 'Dedup po (source, place_id)',
    KEY idx_raw_batch (import_batch_id),
    KEY idx_raw_status (validation_status),
    KEY idx_raw_nip (nip),
    KEY idx_raw_country (country_code),
    KEY idx_raw_business_status (business_status),
    KEY idx_raw_name (name(100)),
    KEY idx_raw_email (email),
    KEY idx_raw_promoted (promoted_to_lead_id),
    KEY idx_raw_imported (imported_at DESC),

    CONSTRAINT fk_raw_source FOREIGN KEY (source_id) REFERENCES intel_lead_sources(id)
    -- promoted_to_lead_id FK dorzucamy po imporcie pierwszych danych, bo na razie intel_leads jest puste
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Staging table — surowe leady ze wszystkich źródeł. Walidacja → promocja do intel_leads.';

-- =====================================================
-- ALTER intel_leads — dodaj wskaźnik na źródłowy wiersz w staging
-- =====================================================
ALTER TABLE intel_leads
    ADD COLUMN promoted_from_raw_id BIGINT UNSIGNED COMMENT 'Wskaźnik na intel_raw_leads.id z którego promowany',
    ADD KEY idx_lead_raw (promoted_from_raw_id);

-- FK dodajemy osobno (gdyby kiedyś chcieć ON DELETE CASCADE, łatwiej manipulować)
-- ALTER TABLE intel_leads
--     ADD CONSTRAINT fk_lead_raw FOREIGN KEY (promoted_from_raw_id) REFERENCES intel_raw_leads(id);

-- =====================================================
-- ZAPIS MIGRACJI
-- =====================================================
INSERT INTO intel_migrations (filename, notes) VALUES
    ('002_staging_table.sql', 'Staging table intel_raw_leads (Outscraper schema + meta + enrichment) + ALTER intel_leads.promoted_from_raw_id')
ON DUPLICATE KEY UPDATE notes = VALUES(notes);

-- =====================================================
-- WERYFIKACJA
-- =====================================================
-- Po zaaplikowaniu uruchom:
--   SHOW TABLES;
--   DESCRIBE intel_raw_leads;
--   SELECT COUNT(*) AS column_count FROM information_schema.columns WHERE table_schema='vivcom_intel' AND table_name='intel_raw_leads';
--   -- Powinno zwrócić: 135 kolumn
--   SELECT * FROM intel_migrations;
