-- intel-platform — migration 002: staging table for raw lead data
-- Target: MariaDB 10.6+ (Zenbox vivcom_intel)
-- Pattern: staging table (intel_raw_leads) → walidacja → promocja do intel_leads (CRM)
--
-- v2 (2026-05-20): Naprawiony row size — długie VARCHAR-y zamienione na TEXT.
-- InnoDB ma limit 65535 bajtów na wiersz w utf8mb4. TEXT trzyma się off-page (pointer in-row).
-- Wszystkie URL-e, social media, długie nazwy → TEXT. VARCHAR zachowany dla pól wyszukiwanych.

-- Idempotentność: jeśli reapply, czyść poprzednią próbę
DROP TABLE IF EXISTS intel_raw_leads;

-- =====================================================
-- STAGING TABLE: intel_raw_leads
-- =====================================================
CREATE TABLE intel_raw_leads (
    id                              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    -- =====================================================
    -- META (zarządzanie wierszami)
    -- =====================================================
    source_id                       INT UNSIGNED NOT NULL COMMENT 'FK do intel_lead_sources',
    import_batch_id                 VARCHAR(100) COMMENT 'np. outscraper_2026-05-20_PL_eventowa',
    source_external_id              VARCHAR(255) COMMENT 'place_id (Outscraper) lub ID z Jitbita',
    imported_at                     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at                    DATETIME,
    updated_at                      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    -- =====================================================
    -- VALIDATION STATUS
    -- =====================================================
    validation_status               ENUM(
                                        'new',
                                        'in_progress',
                                        'validated_ok',
                                        'validated_failed',
                                        'promoted',
                                        'rejected',
                                        'manual_review'
                                    ) NOT NULL DEFAULT 'new',
    validation_notes                TEXT,
    promoted_to_lead_id             BIGINT UNSIGNED,
    promoted_at                     DATETIME,

    -- =====================================================
    -- ENRICHMENT (uzupełniane przez nasze walidatory)
    -- =====================================================
    nip                             VARCHAR(20) COMMENT 'Numer NIP (10 cyfr)',
    regon                           VARCHAR(20),
    krs                             VARCHAR(20),
    pkd                             VARCHAR(20) COMMENT 'Główny kod PKD',
    legal_form                      VARCHAR(50),
    vat_active                      TINYINT(1) COMMENT '1=aktywny, 0=wykreślony',

    -- =====================================================
    -- OUTSCRAPER FIELDS (121 kolumn 1:1)
    -- =====================================================

    -- Query i identyfikacja
    query                           VARCHAR(500),
    name                            VARCHAR(500),
    name_for_emails                 VARCHAR(500),
    subtypes                        TEXT,
    category                        VARCHAR(200),
    type                            VARCHAR(200),

    -- Telefon + enrichment
    phone                           VARCHAR(50),
    phone_phones_enricher_carrier_name      VARCHAR(200),
    phone_phones_enricher_carrier_type      VARCHAR(50),

    -- Website + adres
    website                         TEXT,
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

    -- Company-level
    company_name                    VARCHAR(500),
    company_phone                   VARCHAR(50),
    company_phone_phones_enricher_carrier_name      VARCHAR(200),
    company_phone_phones_enricher_carrier_type      VARCHAR(50),
    company_phones                  TEXT,
    company_linkedin                TEXT,
    company_facebook                TEXT,
    company_instagram               TEXT,
    company_x                       TEXT,
    company_youtube                 TEXT,

    -- Contact person
    full_name                       VARCHAR(255),
    first_name                      VARCHAR(100),
    last_name                       VARCHAR(100),
    title                           VARCHAR(200),

    -- Email + walidacja
    email                           VARCHAR(255),
    email_emails_validator_status           VARCHAR(50),
    email_emails_validator_status_details   VARCHAR(255),

    -- Contact phone + socials
    contact_phone                   VARCHAR(50),
    contact_phone_phones_enricher_carrier_type      VARCHAR(50),
    contact_phone_phones_enricher_carrier_name      VARCHAR(200),
    contact_phones                  TEXT,
    contact_linkedin                TEXT,
    contact_facebook                TEXT,
    contact_instagram               TEXT,
    contact_x                       TEXT,

    -- Website intelligence
    website_title                   VARCHAR(500),
    website_description             TEXT,
    website_generator               VARCHAR(255),
    website_has_gtm                 TINYINT(1),
    website_has_fb_pixel            TINYINT(1),

    -- Skąd Outscraper wziął dane
    source                          VARCHAR(50),

    -- Geo
    latitude                        DECIMAL(11, 8),
    longitude                       DECIMAL(11, 8),
    h3                              VARCHAR(20),
    time_zone                       VARCHAR(50),
    plus_code                       VARCHAR(50),
    area_service                    TINYINT(1),

    -- Reviews + ratings
    rating                          DECIMAL(3, 2),
    reviews                         INT UNSIGNED,
    reviews_link                    TEXT,
    reviews_tags                    TEXT,
    reviews_per_score               TEXT,
    reviews_per_score_1             INT UNSIGNED,
    reviews_per_score_2             INT UNSIGNED,
    reviews_per_score_3             INT UNSIGNED,
    reviews_per_score_4             INT UNSIGNED,
    reviews_per_score_5             INT UNSIGNED,

    -- Photos
    photos_count                    INT UNSIGNED,
    photo                           TEXT,
    street_view                     TEXT,
    logo                            TEXT,

    -- Located in
    located_in                      VARCHAR(500),
    located_google_id               VARCHAR(100),

    -- Status + hours (KLUCZOWE)
    business_status                 VARCHAR(50) COMMENT 'OPERATIONAL / CLOSED_TEMPORARILY / CLOSED_PERMANENTLY',
    working_hours                   TEXT,
    working_hours_csv_compatible    TEXT,
    other_hours                     TEXT,
    popular_times                   TEXT,
    typical_time_spent              VARCHAR(100),

    -- Range / prices / links
    `range`                         VARCHAR(50),
    prices                          TEXT,
    reservation_links               TEXT,
    booking_appointment_link        TEXT,
    menu_link                       TEXT,
    order_links                     TEXT,

    -- Description / about
    about                           TEXT,
    description                     TEXT,
    posts                           TEXT,

    -- Verification + owner
    verified                        TINYINT(1),
    owner_id                        VARCHAR(50),
    owner_title                     VARCHAR(500),
    owner_link                      TEXT,

    -- Linki do Maps
    location_link                   TEXT,
    location_reviews_link           TEXT,

    -- Identyfikatory Google
    place_id                        VARCHAR(100),
    google_id                       VARCHAR(100),
    cid                             VARCHAR(50),
    kgmid                           VARCHAR(50),
    reviews_id                      VARCHAR(50),

    -- Company insights
    company_insights_country                VARCHAR(100),
    company_insights_description            TEXT,
    company_insights_employees              INT UNSIGNED,
    company_insights_founded_year           SMALLINT UNSIGNED,
    company_insights_industry               VARCHAR(200),
    company_insights_is_public              TINYINT(1),
    company_insights_linkedin_bio           TEXT,
    company_insights_linkedin_company_page  TEXT,
    company_insights_name                   VARCHAR(500),
    company_insights_revenue                BIGINT UNSIGNED,
    company_insights_timezone               VARCHAR(50),
    company_insights_address                VARCHAR(500),
    company_insights_city                   VARCHAR(200),
    company_insights_facebook_company_page  TEXT,
    company_insights_state                  VARCHAR(200),
    company_insights_zip                    VARCHAR(20),
    company_insights_twitter_handle         VARCHAR(100),
    company_insights_phone                  VARCHAR(50),
    company_insights_phone_phones_enricher_carrier_name     VARCHAR(200),
    company_insights_phone_phones_enricher_carrier_type     VARCHAR(50),
    company_insights_total_money_raised     BIGINT UNSIGNED,

    -- Chain info
    chain_info_chain                VARCHAR(255),

    -- =====================================================
    -- KEYS
    -- =====================================================
    PRIMARY KEY (id),
    UNIQUE KEY uq_raw_source_external (source_id, source_external_id),
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC
  COMMENT='Staging — surowe leady ze wszystkich źródeł.';

-- =====================================================
-- ALTER intel_leads — wskaźnik na źródłowy wiersz w staging
-- =====================================================
ALTER TABLE intel_leads
    ADD COLUMN IF NOT EXISTS promoted_from_raw_id BIGINT UNSIGNED COMMENT 'Wskaźnik na intel_raw_leads.id',
    ADD KEY IF NOT EXISTS idx_lead_raw (promoted_from_raw_id);

-- =====================================================
-- ZAPIS MIGRACJI
-- =====================================================
INSERT INTO intel_migrations (filename, notes) VALUES
    ('002_staging_table.sql', 'Staging table intel_raw_leads v2 (TEXT for long fields, ROW_FORMAT=DYNAMIC)')
ON DUPLICATE KEY UPDATE notes = VALUES(notes), applied_at = CURRENT_TIMESTAMP;
