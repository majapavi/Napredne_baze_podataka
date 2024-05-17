--DROP TABLE igrac, igrac_klub, klub, natjecanje, sezona, statistika;

--------------------------------------------------------------------------------------------------
--Kreiranje tablica

CREATE TABLE automobil (
    registracija VARCHAR(7) PRIMARY KEY,
    marka VARCHAR(50) NOT NULL,
    boja VARCHAR(20),
    napajanje VARCHAR(20) NOT NULL CHECK (napajanje IN ('benzin', 'dizel', 'elektricni')),
    vrsta_mjenjaca VARCHAR(20) NOT NULL CHECK (vrsta_mjenjaca IN ('rucni', 'automatski'))
);

CREATE TABLE osoba (
    oib VARCHAR(11) PRIMARY KEY,
    ime VARCHAR(15) NOT NULL,
    prezime VARCHAR(15) NOT NULL,
    datum_rodenja DATE NOT NULL
    CONSTRAINT provjera_punoljetnosti CHECK (datum_rodenja <= current_date - interval '18 years')
);

CREATE TABLE instruktor (
    oib VARCHAR(11) PRIMARY KEY,
    registracija_automobila VARCHAR(7) NOT NULL,
    FOREIGN KEY (oib) REFERENCES osoba(oib),
    FOREIGN KEY (registracija_automobila) REFERENCES automobil(registracija)
);

CREATE TABLE polaznik (
    oib VARCHAR(11) PRIMARY KEY,
    ukupna_skolarnina DECIMAL(10, 2) NOT NULL,
    uplaceno DECIMAL(10, 2) NOT NULL CHECK (uplaceno < ukupna_skolarnina),
    potrebno_odvesti_sati INTEGER NOT NULL DEFAULT 35,
    polozena_teorija BOOLEAN NOT NULL DEFAULT FALSE,
    polozena_prva_pomoc BOOLEAN NOT NULL DEFAULT FALSE,
    polozena_voznja BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (oib) REFERENCES osoba(oib)
);

CREATE TABLE ispit (
    oib_polaznik VARCHAR(11),
    datum_ispita DATE,
    tip_ispita VARCHAR(20) CHECK (tip_ispita IN ('propisi', 'prva pomoć', 'vožnja')),
    polozen BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (oib_polaznik, datum_ispita, tip_ispita),
    FOREIGN KEY (oib_polaznik) REFERENCES polaznik(oib)
);

CREATE TABLE sati_voznje (
    oib_instruktor VARCHAR(11),
    oib_polaznik VARCHAR(11),
    datum DATE NOT NULL,
    vrijeme TIME NOT NULL,
    opis_sata TEXT,
    PRIMARY KEY (oib_instruktor, oib_polaznik, datum, vrijeme),
    FOREIGN KEY (oib_polaznik) REFERENCES polaznik(oib),
    FOREIGN KEY (oib_instruktor) REFERENCES instruktor(oib)
);

--------------------------------------------------------------------------------------------------
-- Kreiranje/update rutina

CREATE OR REPLACE FUNCTION broj_izlazaka_na_vožnju(oib_polaznika VARCHAR(11)) RETURNS INTEGER AS $$
BEGIN
    RETURN (SELECT count(*) FROM ispit WHERE ispit.oib_polaznik = oib_polaznika);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION odvozio_sati_polaznik(oib_polaznika VARCHAR(11), godina INTEGER DEFAULT NULL) RETURNS INTEGER AS $$
DECLARE
    broj_sati INTEGER;
BEGIN
    IF godina IS NULL THEN
        SELECT COUNT(*) INTO broj_sati FROM sati_voznje
        WHERE sati_voznje.oib_polaznik = oib_polaznika;
    ELSE
        SELECT COUNT(*) INTO broj_sati FROM sati_voznje
        WHERE sati_voznje.oib_polaznik = oib_polaznika AND date_part('year', datum) = godina;
    END IF;
    RETURN broj_sati;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION odvozio_sati_instruktor(oib_instruktora VARCHAR(11), godina INTEGER DEFAULT NULL) RETURNS INTEGER AS $$
DECLARE
    broj_sati INTEGER;
BEGIN
    IF godina IS NULL THEN
        SELECT COUNT(*) INTO broj_sati FROM sati_voznje
        WHERE sati_voznje.oib_instruktor = oib_instruktora;
    ELSE
        SELECT COUNT(*) INTO broj_sati FROM sati_voznje
        WHERE sati_voznje.oib_instruktor = oib_instruktora AND date_part('year', datum) = godina;
    END IF;
    RETURN broj_sati;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION poredak_instrukotora_po_satnici(godina INTEGER)
    RETURNS TABLE (ime VARCHAR(15), prezime VARCHAR(15), satnica_u_godini INTEGER, odstupanje_od_prosjeka INTEGER) AS $$

DECLARE
    prosjecna_satnica INTEGER;
BEGIN
    SELECT AVG(odvozio_sati_instruktor(instruktor.oib, godina)) INTO prosjecna_satnica FROM instruktor;

    RETURN QUERY
    SELECT osoba.ime, osoba.prezime, odvozio_sati_instruktor(instruktor.oib, godina),
            odvozio_sati_instruktor(instruktor.oib, godina) - prosjecna_satnica
    FROM instruktor
    JOIN osoba on instruktor.oib = osoba.oib
    ORDER BY 3 DESC;
END
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------------------------
-- Kreiranje/update triggera i pripadnih funkcija

CREATE OR REPLACE FUNCTION azuriraj_polozeni_ispit() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.polozen THEN
        EXECUTE format('UPDATE polaznik SET %I = TRUE WHERE oib = $1', CASE NEW.tip_ispita
            WHEN 'propisi' THEN 'polozena_teorija'
            WHEN 'prva pomoć' THEN 'polozena_prva_pomoc'
            WHEN 'vožnja' THEN 'polozena_voznja'
        END)
        USING NEW.oib_polaznik;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER azuriraj_polozeni_ispit_trigger AFTER INSERT ON ispit
FOR EACH ROW EXECUTE FUNCTION azuriraj_polozeni_ispit();


CREATE OR REPLACE FUNCTION provjera_uvjeta_za_polaganje_voznje() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.tip_ispita = 'vožnja'
        AND ( (SELECT polozena_teorija FROM polaznik WHERE oib = NEW.oib_polaznik) IS FALSE
        OR (SELECT polozena_prva_pomoc FROM polaznik WHERE oib = NEW.oib_polaznik) IS FALSE
        OR (odvozio_sati_polaznik(NEW.oib_polaznik) < (SELECT potrebno_odvesti_sati FROM polaznik WHERE oib = NEW.oib_polaznik)) ) THEN
        RAISE EXCEPTION 'Nisu ostvareni uvijeti za pristup ispitu iz vožnje!';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER provjera_ispita_trigger BEFORE INSERT ON ispit
FOR EACH ROW EXECUTE FUNCTION provjera_uvjeta_za_polaganje_voznje();


CREATE OR REPLACE FUNCTION provjeri_prvu_ratu() RETURNS TRIGGER AS $$
BEGIN
	IF NEW.uplaceno < NEW.ukupna_skolarnina / 3 THEN
		RAISE EXCEPTION 'Prva rata mora biti najmanje trećina ukupne školarine!';
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER provjeri_prvu_ratu_trigger BEFORE INSERT ON polaznik
FOR EACH ROW EXECUTE FUNCTION provjeri_prvu_ratu();


CREATE OR REPLACE FUNCTION dodaj_sate_nakon_pada_voznje() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.tip_ispita = 'vožnja' AND NEW.polozen = FALSE THEN
        UPDATE polaznik
        SET potrebno_odvesti_sati = potrebno_odvesti_sati + 3
        WHERE oib = NEW.oib_polaznik;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER dodaj_sate_trigger AFTER INSERT ON ispit
FOR EACH ROW EXECUTE FUNCTION dodaj_sate_nakon_pada_voznje();

--------------------------------------------------------------------------------------------------
-- Kreiranje/update pogleda

CREATE OR REPLACE VIEW stanje_aktivnih_polaznika AS
SELECT
    osoba.ime AS ime,
    osoba.prezime AS prezime,
    polaznik.uplaceno AS uplaćeno,
    (polaznik.ukupna_skolarnina - polaznik.uplaceno) AS preostalo_uplatiti,
    odvozio_sati_polaznik(polaznik.oib) AS odvezeno_sati,
    broj_izlazaka_na_vožnju(polaznik.oib) AS izlasci_na_ispit_iz_vožnje,
    (polaznik.potrebno_odvesti_sati - 35) AS određeno_dodatnih_sati,
    CASE WHEN polaznik.polozena_teorija THEN 'Da' ELSE 'Ne' END AS položena_teorija,
    CASE WHEN polaznik.polozena_prva_pomoc THEN 'Da' ELSE 'Ne' END AS položena_prva_pomoć,
    CASE WHEN polaznik.polozena_voznja THEN 'Da' ELSE 'Ne' END AS položena_vožnja
FROM polaznik
JOIN osoba ON polaznik.oib = osoba.oib
WHERE polaznik.polozena_voznja IS FALSE
ORDER BY osoba.prezime, osoba.ime;

--------------------------------------------------------------------------------------------------
-- Kreiranje indexa

CREATE INDEX idx_ispit_oib_polaznika ON ispit (oib_polaznik);
CREATE INDEX idx_sati_voznje_oib_polaznika ON sati_voznje (oib_polaznik);
CREATE INDEX idx_sati_voznje_oib_instruktora_datum ON sati_voznje (oib_instruktor, datum);

--------------------------------------------------------------------------------------------------
-- Unos podataka

-- Unos automobila
INSERT INTO automobil (registracija, marka, boja, napajanje, vrsta_mjenjaca)
VALUES
    ('1234567', 'Volkswagen Golf', 'Crna', 'benzin', 'rucni'),
    ('2345678', 'Toyota Corolla', 'Siva', 'benzin', 'automatski'),
    ('3456789', 'Tesla Model S', 'Bijela', 'elektricni', 'automatski');

-- Unos osoba
INSERT INTO osoba (oib, ime, prezime, datum_rodenja)
VALUES
    ('12345678901', 'Ana', 'Anić', '1990-05-15'),
    ('23456789012', 'Ivan', 'Ivanić', '1985-08-20'),
    ('34567890123', 'Mate', 'Matić', '2000-02-10'),
    ('56789012345', 'Petar', 'Petrić', '1998-06-10'),
    ('67890123456', 'Iva', 'Ivić', '2002-03-20'),
    ('78901234567', 'Marko', 'Marković', '1995-12-05'),
    ('90123456789', 'Domagoj', 'Vidrić', '1944-06-02');

-- Unos instruktora
INSERT INTO instruktor (oib, registracija_automobila)
VALUES
    ('12345678901', '1234567'),
    ('23456789012', '2345678'),
    ('90123456789', '3456789');

-- Unos polaznika
INSERT INTO polaznik (oib, ukupna_skolarnina, uplaceno, polozena_teorija, polozena_prva_pomoc, polozena_voznja)
VALUES
    ('56789012345', 1800.00, 600.00, FALSE, FALSE, FALSE),
    ('67890123456', 2200.00, 800.00, FALSE, FALSE, FALSE),
    ('78901234567', 1900.00, 1000.00, TRUE, FALSE, FALSE),
    ('34567890123', 1500.00, 500.00, FALSE, FALSE, FALSE);

-- Update polaznika '78901234567'
UPDATE polaznik
SET polozena_teorija=TRUE, polozena_prva_pomoc=TRUE
WHERE oib='78901234567';

-- Unos ispita
INSERT INTO ispit (oib_polaznik, datum_ispita, tip_ispita, polozen)
VALUES
    ('34567890123', '2024-04-01', 'propisi', FALSE),
    ('34567890123', '2024-04-02', 'prva pomoć', TRUE),
    ('34567890123', '2024-04-03', 'propisi', TRUE);

-- Unos pojedinačnih sati vožnje
INSERT INTO sati_voznje (oib_instruktor, oib_polaznik, datum, vrijeme, opis_sata)
VALUES
    ('12345678901', '34567890123', '2024-03-25', '10:00', 'Parkiranje'),
    ('12345678901', '34567890123', '2024-03-27', '11:30', 'Vožnja po gradu'),
    ('23456789012', '34567890123', '2024-03-29', '09:00', 'Vožnja na autocesti');

-- Unos 14 sati vožnje polazniku '78901234567'
WITH datumi AS (
    SELECT current_date - interval '1' day * generate_series(1, 14) AS datum
)
INSERT INTO sati_voznje (oib_instruktor, oib_polaznik, datum, vrijeme, opis_sata)
SELECT
    '90123456789' AS oib_instruktor,
    '78901234567' AS oib_polaznik,
    datumi.datum,
    make_time(floor(random() * 24)::int, floor(random() * 60)::int, floor(random() * 60)::int) AS vrijeme,
    'Praktična vožnja' AS opis_sata
FROM datumi;

-- Unos 35 sati vožnje polazniku '78901234567'
WITH datumi AS (
    SELECT current_date - interval '1' day * generate_series(1, 35) AS datum
)
INSERT INTO sati_voznje (oib_instruktor, oib_polaznik, datum, vrijeme, opis_sata)
SELECT
    '23456789012' AS oib_instruktor,
    '34567890123' AS oib_polaznik,
    datumi.datum,
    make_time(floor(random() * 24)::int, floor(random() * 60)::int, floor(random() * 60)::int) AS vrijeme,
    'Gradska vožnja' AS opis_sata
FROM datumi;

-- Unos ispita iz vožnje polazniku '34567890123'
INSERT INTO ispit (oib_polaznik, datum_ispita, tip_ispita, polozen)
VALUES
	('34567890123', '2024-04-02', 'vožnja', TRUE);

--------------------------------------------------------------------------------------------------
-- Testni upiti

SELECT * FROM polaznik;
SELECT * FROM instruktor;
SELECT * FROM sati_voznje;

SELECT odvozio_sati_polaznik('34567890123', 2024);
SELECT * FROM odvozio_sati_instruktor('23456789012',2024);

SELECT * FROM stanje_aktivnih_polaznika;
SELECT * FROM poredak_instrukotora_po_satnici(2024);


