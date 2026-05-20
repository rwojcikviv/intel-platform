-- intel-platform — initial schema (migration 001)
-- Target: MariaDB 10.6+ (Zenbox vivcom_intel)
-- Strategy: prefix all tables with intel_ to avoid conflict with vivcom_prod tables.
-- MVP scope: leads + categories + verifications. Signals/snapshots come in 002.

-- =====================================================
-- 1. Business units (najwyższy poziom hierarchii)
-- =====================================================
CREATE TABLE IF NOT EXISTS intel_business_units (
    id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
    code            VARCHAR(50) NOT NULL,
    name            VARCHAR(200) NOT NULL,
    description     TEXT,
    is_active       TINYINT(1) NOT NULL DEFAULT 1,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    PRIMARY KEY (id),
    UNIQUE KEY uq_bu_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- 2. Categories (per business unit)
-- =====================================================
CREATE TABLE IF NOT EXISTS intel_categories (
    id                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    business_unit_id    INT UNSIGNED NOT NULL,
    code                VARCHAR(50) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,
    is_active           TINYINT(1) NOT NULL DEFAULT 1,
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    PRIMARY KEY (id),
    UNIQUE KEY uq_cat_bu_code (business_unit_id, code),
    CONSTRAINT fk_cat_bu FOREIGN KEY (business_unit_id) REFERENCES intel_business_units(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- 3. Lead sources (skąd pochodzi lead)
-- =====================================================
CREATE TABLE IF NOT EXISTS intel_lead_sources (
    id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
    code            VARCHAR(50) NOT NULL,
    name            VARCHAR(200) NOT NULL,
    description     TEXT,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    PRIMARY KEY (id),
    UNIQUE KEY uq_src_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- 4. Leads (główna tabela)
-- =====================================================
CREATE TABLE IF NOT EXISTS intel_leads (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    business_unit_id    INT UNSIGNED NOT NULL,
    source_id           INT UNSIGNED NOT NULL,
    external_id         VARCHAR(255),                   -- ID w źródłowym systemie (np. Jitbit ID)
    
    -- Identyfikacja firmy
    company_name        VARCHAR(500),
    nip                 VARCHAR(20),
    regon               VARCHAR(20),
    krs                 VARCHAR(20),
    
    -- Kontakt
    primary_email       VARCHAR(255),
    primary_phone       VARCHAR(50),
    website_url         VARCHAR(1000),
    
    -- Lokalizacja
    country_code        CHAR(2),                        -- ISO 3166-1 alpha-2 (PL, DE, FR...)
    city                VARCHAR(200),
    postcode            VARCHAR(20),
    address             VARCHAR(500),
    
    -- Status walidacji (high-level; szczegóły w intel_verifications)
    status              ENUM('unverified', 'active', 'dormant', 'dead', 'archived', 'error') 
                        NOT NULL DEFAULT 'unverified',
    last_verified_at    DATETIME,
    
    -- Audyt
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    PRIMARY KEY (id),
    KEY idx_lead_bu (business_unit_id),
    KEY idx_lead_source (source_id),
    KEY idx_lead_status (status),
    KEY idx_lead_country (country_code),
    KEY idx_lead_nip (nip),
    KEY idx_lead_external (source_id, external_id),
    KEY idx_lead_company (company_name),
    
    CONSTRAINT fk_lead_bu FOREIGN KEY (business_unit_id) REFERENCES intel_business_units(id),
    CONSTRAINT fk_lead_source FOREIGN KEY (source_id) REFERENCES intel_lead_sources(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- 5. Lead-Category mapping (many-to-many)
-- =====================================================
CREATE TABLE IF NOT EXISTS intel_lead_categories (
    lead_id         BIGINT UNSIGNED NOT NULL,
    category_id     INT UNSIGNED NOT NULL,
    confidence      DECIMAL(3,2),                       -- 0.00-1.00, jak pewni klasyfikacji
    assigned_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    assigned_by     VARCHAR(50),                        -- np. 'import', 'pkd_classifier', 'manual'
    
    PRIMARY KEY (lead_id, category_id),
    KEY idx_lc_cat (category_id),
    
    CONSTRAINT fk_lc_lead FOREIGN KEY (lead_id) REFERENCES intel_leads(id) ON DELETE CASCADE,
    CONSTRAINT fk_lc_cat FOREIGN KEY (category_id) REFERENCES intel_categories(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- 6. Verifications (każda weryfikacja zostawia ślad)
-- =====================================================
CREATE TABLE IF NOT EXISTS intel_verifications (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    lead_id         BIGINT UNSIGNED NOT NULL,
    verifier        VARCHAR(50) NOT NULL,               -- np. 'url_liveness', 'biala_lista_vat', 'gus_regon'
    status          VARCHAR(50) NOT NULL,               -- np. 'active', 'inactive', 'not_found', 'error', 'timeout'
    result_data     JSON,                               -- pełne wyniki (raw response)
    notes           TEXT,                               -- opcjonalne notatki
    checked_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    PRIMARY KEY (id),
    KEY idx_ver_lead (lead_id),
    KEY idx_ver_verifier (verifier),
    KEY idx_ver_checked (checked_at DESC),
    KEY idx_ver_lead_verifier (lead_id, verifier, checked_at DESC),
    
    CONSTRAINT fk_ver_lead FOREIGN KEY (lead_id) REFERENCES intel_leads(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- 7. Migration log (śledzenie zastosowanych migracji)
-- =====================================================
CREATE TABLE IF NOT EXISTS intel_migrations (
    id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
    filename        VARCHAR(255) NOT NULL,
    applied_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes           TEXT,
    
    PRIMARY KEY (id),
    UNIQUE KEY uq_mig_file (filename)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- SEED DATA
-- =====================================================

INSERT INTO intel_business_units (code, name, description) VALUES
    ('viv', 'VIV — dmuchańce i karuzele', 'Główny biznes: producent dmuchańców i karuzel mobilnych'),
    ('modular', 'Modular Construction', 'Budownictwo modułowe — niezależny produkt')
ON DUPLICATE KEY UPDATE name = VALUES(name);

INSERT INTO intel_categories (business_unit_id, code, name, description) VALUES
    ((SELECT id FROM intel_business_units WHERE code='viv'),     'dmuchance',           'Dmuchańce',           'Dmuchańce eventowe, rekreacyjne, reklamowe'),
    ((SELECT id FROM intel_business_units WHERE code='viv'),     'karuzele_rodeo',      'Karuzele i rodeo',    'Karuzele mobilne, rodeo byk, atrakcje mechaniczne'),
    ((SELECT id FROM intel_business_units WHERE code='modular'), 'budownictwo_modulowe', 'Budownictwo modułowe', 'Konstrukcje modułowe, pawilony, kontenery')
ON DUPLICATE KEY UPDATE name = VALUES(name);

INSERT INTO intel_lead_sources (code, name, description) VALUES
    ('jitbit',         'Jitbit CRM migration',  'Stary CRM, jednorazowy import historyczny'),
    ('lead_pipeline',  'lead-pipeline scrapers', 'Skrypty pozyskiwania z C:\\lead-pipeline\\'),
    ('manual',         'Manual entry',          'Ręcznie dodane przez użytkownika')
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- Zapisz info o tej migracji
INSERT INTO intel_migrations (filename, notes) VALUES
    ('001_initial_schema.sql', 'Initial schema: business_units, categories, lead_sources, leads, lead_categories, verifications')
ON DUPLICATE KEY UPDATE notes = VALUES(notes);

-- =====================================================
-- WERYFIKACJA INSTALACJI
-- =====================================================
-- Po zaaplikowaniu uruchom:
--   SHOW TABLES;
--   SELECT * FROM intel_business_units;
--   SELECT * FROM intel_categories;
--   SELECT * FROM intel_lead_sources;
--   SELECT * FROM intel_migrations;
