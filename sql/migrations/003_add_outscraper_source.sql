-- intel-platform — migration 003: add outscraper_gmaps source

INSERT INTO intel_lead_sources (code, name, description) VALUES
    ('outscraper_gmaps', 'Outscraper — Google Maps', 'Eksport XLSX z Outscrapera, Google Maps + enrichment')
ON DUPLICATE KEY UPDATE name = VALUES(name), description = VALUES(description);

INSERT INTO intel_migrations (filename, notes) VALUES
    ('003_add_outscraper_source.sql', 'Added outscraper_gmaps source')
ON DUPLICATE KEY UPDATE notes = VALUES(notes), applied_at = CURRENT_TIMESTAMP;
