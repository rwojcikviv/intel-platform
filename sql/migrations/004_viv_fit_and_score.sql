-- intel-platform — migration 004: viv_fit classification + lead_score
--
-- Cel: oznaczyć leady kategoriami pod kątem dopasowania do oferty VIV
-- (dmuchańce, karuzele, atrakcje), oraz wyliczyć score do prioritetyzacji.
--
-- Klasyfikacja:
--   priority_1 = bezpośredni kupcy (wypożyczalnie dmuchańców i pokrewne)
--   priority_2 = stałe lokalizacje (place zabaw, parki rozrywki, aquaparki)
--   priority_3 = organizatorzy eventów (kupują rzadziej, wynajmują)
--   low        = pośrednicy z niskim conversion (agencje reklamowe/marketingowe)
--   none       = poza targetem (teatry, muzea, restauracje)
--   competitor = konkurenci VIV (inni producenci dmuchańców/sal zabaw)
--   unknown    = NULL kategoria lub nieznane — wymaga manual review

-- =====================================================
-- ALTER TABLE — dodaj viv_fit + lead_score
-- =====================================================
ALTER TABLE intel_raw_leads
    ADD COLUMN IF NOT EXISTS viv_fit ENUM(
        'priority_1',
        'priority_2',
        'priority_3',
        'low',
        'none',
        'competitor',
        'unknown'
    ) NOT NULL DEFAULT 'unknown'
      COMMENT 'Klasyfikacja dopasowania do oferty VIV'
      AFTER validation_notes,
    ADD COLUMN IF NOT EXISTS lead_score DECIMAL(6,2)
      COMMENT 'Wyliczony score 0-100, im wyższy tym lepszy lead'
      AFTER viv_fit,
    ADD KEY IF NOT EXISTS idx_raw_viv_fit (viv_fit),
    ADD KEY IF NOT EXISTS idx_raw_score (lead_score DESC);

-- =====================================================
-- BULK UPDATE viv_fit na podstawie category
-- =====================================================

-- PRIORITY 1 — bezpośredni kupcy B2B
UPDATE intel_raw_leads SET viv_fit = 'priority_1'
WHERE category IN (
    'Wynajem dmuchańców',
    'Wypożyczalnia namiotów',
    'Wypożyczalnia sprzętu na przyjęcia',
    'Wypożyczalnia zabawek',
    'Animator – skręcanie balonów'
);

-- PRIORITY 2 — stałe lokalizacje kupujące na własność
UPDATE intel_raw_leads SET viv_fit = 'priority_2'
WHERE category IN (
    'Plac zabaw',
    'Sala zabaw',
    'Park rozrywki',
    'Park wodny',
    'Centrum rozrywki',
    'Centrum rekreacyjno-sportowe',
    'Obiekt przeznaczony do organizacji imprez',
    'Playground',
    'attractions'  -- mix premium klientów, manual review później dla zamków/muzeów
);

-- PRIORITY 3 — organizatorzy / wynajmujący
UPDATE intel_raw_leads SET viv_fit = 'priority_3'
WHERE category IN (
    'Organizator imprez',
    'Firma zajmująca się organizacją imprez i konferencji',
    'Obsługa przyjęć dla dzieci',
    'Event management company',
    'Wynajem namiotów',
    'Urządzenia do obsługi imprez masowych',
    'Agencja artystyczna'
);

-- LOW — pośrednicy z niskim conversion
UPDATE intel_raw_leads SET viv_fit = 'low'
WHERE category IN (
    'Agencja reklamowa',
    'Agencja marketingowa',
    'Wypożyczalnia mebli',
    'Siedziba firmy'
);

-- NONE — poza targetem
UPDATE intel_raw_leads SET viv_fit = 'none'
WHERE category IN (
    'museums',
    'Teatr',
    'restaurants'
);

-- COMPETITOR — konkurenci VIV
UPDATE intel_raw_leads SET viv_fit = 'competitor'
WHERE category = 'Producent';

-- Pozostałe (NULL category, nieznane) zostają 'unknown' — DEFAULT z ALTER

-- =====================================================
-- BULK UPDATE lead_score
-- =====================================================
-- Formuła:
--   base = log10(reviews + 1) × IFNULL(rating, 3.5)
--   × fit_multiplier (P1=2.0, P2=1.5, P3=1.0, low=0.5, none=0.1, competitor=0, unknown=0.7)
--   × email_multiplier (mail=1.2, brak=0.7)
--   × verified_multiplier (verified=1.1, brak=1.0)
--   × linkedin_multiplier (ma=1.2, brak=1.0)
--   × status_multiplier (OPERATIONAL=1.0, CLOSED_TEMPORARILY=0.7, CLOSED_PERMANENTLY=0)

UPDATE intel_raw_leads
SET lead_score = ROUND(
    LOG10(IFNULL(reviews, 0) + 1) * IFNULL(rating, 3.5)
    * CASE viv_fit
        WHEN 'priority_1' THEN 2.0
        WHEN 'priority_2' THEN 1.5
        WHEN 'priority_3' THEN 1.0
        WHEN 'low'        THEN 0.5
        WHEN 'none'       THEN 0.1
        WHEN 'competitor' THEN 0.0
        WHEN 'unknown'    THEN 0.7
      END
    * CASE WHEN email IS NOT NULL THEN 1.2 ELSE 0.7 END
    * CASE WHEN verified = 1 THEN 1.1 ELSE 1.0 END
    * CASE WHEN company_insights_linkedin_company_page IS NOT NULL THEN 1.2 ELSE 1.0 END
    * CASE business_status
        WHEN 'OPERATIONAL'        THEN 1.0
        WHEN 'CLOSED_TEMPORARILY' THEN 0.7
        WHEN 'CLOSED_PERMANENTLY' THEN 0.0
        ELSE 0.8
      END,
    2
);

-- =====================================================
-- ZAPIS MIGRACJI
-- =====================================================
INSERT INTO intel_migrations (filename, notes) VALUES
    ('004_viv_fit_and_score.sql',
     'viv_fit ENUM classification + lead_score formula, bulk UPDATE z kategorii Outscrapera')
ON DUPLICATE KEY UPDATE notes = VALUES(notes), applied_at = CURRENT_TIMESTAMP;

-- =====================================================
-- WERYFIKACJA — po zaaplikowaniu uruchom:
-- =====================================================
-- 1) Rozkład viv_fit:
--    SELECT viv_fit, COUNT(*) AS n FROM intel_raw_leads GROUP BY viv_fit ORDER BY n DESC;
--
-- 2) Top 30 leadów per fit (priority_1 = wypożyczalnie):
--    SELECT name, city, viv_fit, lead_score, reviews, rating
--    FROM intel_raw_leads
--    WHERE viv_fit = 'priority_1' AND business_status='OPERATIONAL'
--    ORDER BY lead_score DESC LIMIT 30;
--
-- 3) Top per region:
--    SELECT name, city, category, viv_fit, lead_score, reviews
--    FROM intel_raw_leads
--    WHERE city IN ('Katowice','Sosnowiec','Chorzów') AND viv_fit IN ('priority_1','priority_2')
--    ORDER BY lead_score DESC LIMIT 30;
