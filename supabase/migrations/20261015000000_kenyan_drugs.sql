-- Common Kenyan medicines for the drug search.
--
-- The catalogue held 8 drugs, so most searches missed it and fell through to
-- OpenFDA: slower, US brand names, and no safety flags. This adds medicines
-- from the Kenya Essential Medicines List 2023 that people commonly look
-- up, and the brand names they search by. Diclofenac is the one exception:
-- not on KEML 2023, but widely sold and searched for.
--
-- Mirrors assets/seed/drugs.json (the seed.sql source), so a fresh database
-- ends up the same either way. Safe to re-run: rows are matched by name.
--
-- Safety flags are conservative: true only where use is well established;
-- anything that needs a clinician's judgement is false.

update public.drugs set uses = 'Treats bacterial infections including pneumonia, ear infections, UTIs, and skin infections. Common brands in Kenya: Amoxil.' where name = 'Amoxicillin';
update public.drugs set uses = 'Relieves mild to moderate pain and reduces fever. Common brands in Kenya: Panadol, Calpol.' where name = 'Paracetamol';
update public.drugs set uses = 'Controls blood sugar levels in type 2 diabetes. Common brands in Kenya: Glucophage.' where name = 'Metformin';
update public.drugs set uses = 'Reduces pain, fever and inflammation. Used for headaches, arthritis, menstrual cramps. Common brands in Kenya: Brufen.' where name = 'Ibuprofen';
update public.drugs set uses = 'Treats urinary tract infections, respiratory infections, typhoid fever. Common brands in Kenya: Ciproxin.' where name = 'Ciprofloxacin';
update public.drugs set uses = 'First-line treatment for uncomplicated malaria in Kenya. Common brands in Kenya: Coartem.' where name = 'Artemether/Lumefantrine';
update public.drugs set uses = 'Treats acid reflux, stomach ulcers, and heartburn. Common brands in Kenya: Losec.' where name = 'Omeprazole';
update public.drugs set uses = 'Treats high blood pressure and chest pain (angina). Common brands in Kenya: Norvasc.' where name = 'Amlodipine';

insert into public.drugs (name, generic_name, category, uses, dosage, side_effects, pregnancy_safe, alcohol_safe, lactation_safe, prescription_required)
select * from (values
  ('Metronidazole', 'Metronidazole', 'Antibiotic / Antiprotozoal', 'Treats amoebic dysentery, giardiasis, bacterial vaginosis, trichomoniasis and other anaerobic infections. Common brands in Kenya: Flagyl.', 'Adults: 400mg every 8 hours for 5-7 days, depending on the infection. Complete the full course.', 'Metallic taste, nausea, dark urine. Drinking alcohol during treatment and for 48 hours after can cause severe vomiting and flushing.', false, false, false, 'Yes'),
  ('Cotrimoxazole', 'Sulfamethoxazole + Trimethoprim', 'Antibiotic', 'Treats urinary tract and chest infections, and prevents infections in people living with HIV. Common brands in Kenya: Septrin.', 'Adults: 960mg twice daily for treatment. For prevention in HIV: 960mg once daily, as directed by your clinic.', 'Nausea, rash. Stop and seek care urgently if a rash, blisters or mouth sores appear.', false, false, false, 'Yes'),
  ('Amoxicillin/Clavulanic Acid', 'Amoxicillin + Clavulanic Acid', 'Antibiotic', 'Treats sinus, ear, chest, skin and urinary infections, and infected bites. Common brands in Kenya: Augmentin.', 'Adults: 625mg every 8 hours or 1g twice daily for 5-7 days, with food.', 'Diarrhoea, nausea, oral or vaginal thrush, rash. Rarely, liver problems.', false, false, true, 'Yes'),
  ('Doxycycline', 'Doxycycline', 'Antibiotic', 'Treats chest infections, chlamydia and other STIs, and acne; also used to prevent malaria when travelling.', 'Adults: usually 200mg on day 1, then 100mg daily, as prescribed. Swallow with a full glass of water while sitting upright. Not for children under 8.', 'Sunburn more easily, nausea, heartburn or throat irritation if taken lying down.', false, false, false, 'Yes'),
  ('Azithromycin', 'Azithromycin', 'Antibiotic', 'Treats chest infections, typhoid, trachoma and some sexually transmitted infections. Common brands in Kenya: Zithromax.', 'Adults: commonly 500mg once daily for 3 days; some infections use a single dose. Follow the prescription.', 'Diarrhoea, nausea, stomach pain.', false, false, false, 'Yes'),
  ('Flucloxacillin', 'Flucloxacillin', 'Antibiotic', 'Treats skin and soft-tissue infections such as boils, cellulitis and infected wounds.', 'Adults: 250-500mg every 6 hours, 1 hour before food, usually for 5-7 days.', 'Nausea, diarrhoea, rash. Rarely, jaundice, which can appear weeks after the course.', true, false, true, 'Yes'),
  ('Nitrofurantoin', 'Nitrofurantoin', 'Antibiotic', 'Treats and prevents uncomplicated urinary tract infections (bladder infections).', 'Adults: 100mg every 12 hours with food for 5 days, or as prescribed.', 'Nausea, harmless brown urine. Rarely, lung or liver reactions with long-term use.', false, false, false, 'Yes'),
  ('Ceftriaxone', 'Ceftriaxone', 'Antibiotic', 'Injection for serious infections such as meningitis, severe pneumonia, typhoid and gonorrhoea. Common brands in Kenya: Rocephin.', 'Adults: 1-2g once daily by injection, given by a health worker.', 'Pain at the injection site, diarrhoea, rash.', false, false, false, 'Yes'),
  ('Dihydroartemisinin/Piperaquine', 'Dihydroartemisinin + Piperaquine', 'Antimalarial', 'Treats uncomplicated malaria; an alternative to artemether/lumefantrine. Common brands in Kenya: Duo-Cotecxin, P-Alaxin.', 'Once daily for 3 days, dose by body weight. Take on an empty stomach, not with fatty food.', 'Headache, dizziness, nausea, palpitations.', false, false, false, 'Yes'),
  ('Artesunate Injection', 'Artesunate', 'Antimalarial', 'Treats severe malaria in hospital, until the patient can take tablets.', 'Given by injection in hospital, dose by body weight, followed by a full course of tablets.', 'Dizziness, nausea. Rarely, anaemia in the weeks after treatment.', false, false, false, 'Yes'),
  ('Sulfadoxine/Pyrimethamine', 'Sulfadoxine + Pyrimethamine', 'Antimalarial', 'Prevents malaria in pregnancy (IPTp), from the second trimester, given at the antenatal clinic. Not given to women taking cotrimoxazole. Common brands in Kenya: Fansidar.', '3 tablets as a single dose, at scheduled antenatal visits at least one month apart.', 'Nausea. Stop and seek care urgently if a rash, blisters or mouth sores appear.', true, false, false, 'Yes'),
  ('Albendazole', 'Albendazole', 'Anthelmintic (Dewormer)', 'Treats and prevents intestinal worms such as roundworm, hookworm and whipworm. Common brands in Kenya: Zentel.', 'Adults and children over 2: 400mg as a single dose. Children 1-2 years: 200mg.', 'Stomach pain, nausea, headache.', false, false, false, 'No'),
  ('Praziquantel', 'Praziquantel', 'Anthelmintic (Dewormer)', 'Treats bilharzia (schistosomiasis) and tapeworm. Common brands in Kenya: Biltricide.', 'Bilharzia: 40mg/kg body weight as a single dose, with food. 600mg tablets.', 'Dizziness, drowsiness, headache, stomach pain, nausea.', false, false, false, 'Yes'),
  ('Mebendazole', 'Mebendazole', 'Anthelmintic (Dewormer)', 'Treats intestinal worms including threadworm, roundworm and hookworm. Common brands in Kenya: Vermox.', 'Adults and children over 2: 500mg as a single dose, or 100mg twice daily for 3 days.', 'Stomach pain, diarrhoea.', false, false, false, 'No'),
  ('Oral Rehydration Salts (ORS)', 'Oral Rehydration Salts', 'Rehydration', 'Replaces water and salts lost through diarrhoea or vomiting. The first treatment for diarrhoea at any age.', 'Mix one sachet with the amount of clean water on the pack. Sip often. After each loose stool: children under 2, 50-100ml; children 2-10, 100-200ml; older children and adults, as much as wanted.', 'Vomiting if drunk too quickly; wait 10 minutes and continue more slowly.', true, true, true, 'No'),
  ('Zinc Sulfate', 'Zinc Sulfate', 'Supplement', 'Given with ORS to children with diarrhoea; shortens the illness and helps prevent the next episode.', 'Children 6 months and over: 20mg once daily for 10-14 days. Under 6 months: 10mg daily. Dissolve the tablet in a little water or breast milk.', 'Nausea or vomiting, especially on an empty stomach.', true, true, true, 'No'),
  ('Loperamide', 'Loperamide', 'Antidiarrhoeal', 'Short-term relief of acute diarrhoea in adults. Common brands in Kenya: Imodium.', 'Adults: 4mg at first, then 2mg after each loose stool. Max 16mg/day. Not for children under 12, or for diarrhoea with blood or fever.', 'Constipation, stomach cramps, dizziness.', false, false, false, 'No'),
  ('Ferrous Sulfate/Folic Acid', 'Iron + Folic Acid (IFAS)', 'Supplement', 'Prevents anaemia in pregnancy and helps prevent birth defects of the spine and brain.', 'One tablet (60mg elemental iron + 400mcg folic acid) daily throughout pregnancy, as given at the antenatal clinic. Best taken between meals.', 'Dark stools, constipation, nausea.', true, true, true, 'No'),
  ('Salbutamol Inhaler', 'Salbutamol', 'Bronchodilator', 'Quickly relieves wheezing and breathlessness in asthma and COPD. Common brands in Kenya: Ventolin.', '1-2 puffs (100-200mcg) when needed, up to 4 times a day. Needing it more often means asthma is not controlled: see a clinician.', 'Shaky hands, fast heartbeat, headache.', true, true, true, 'Yes'),
  ('Prednisolone', 'Prednisolone', 'Corticosteroid', 'Reduces inflammation in severe asthma attacks, allergic reactions and some skin and joint conditions.', 'Dose depends on the condition, e.g. 40-50mg once daily for 5 days in an asthma attack. Take in the morning with food. Do not stop suddenly after a long course.', 'Raised blood sugar, mood changes, stomach irritation, higher risk of infection.', false, false, false, 'Yes'),
  ('Cetirizine', 'Cetirizine', 'Antihistamine', 'Relieves hay fever, itchy skin, hives and other allergies. Common brands in Kenya: Zyrtec.', 'Adults: 10mg once daily.', 'Mild drowsiness, dry mouth, headache.', false, false, false, 'No'),
  ('Chlorphenamine', 'Chlorpheniramine Maleate', 'Antihistamine', 'Relieves allergies, hay fever, itching and insect bites. Common brands in Kenya: Piriton.', 'Adults: 4mg every 4-6 hours. Max 24mg/day.', 'Drowsiness (do not drive), dry mouth, blurred vision.', false, false, false, 'No'),
  ('Hydrochlorothiazide', 'Hydrochlorothiazide', 'Antihypertensive (Diuretic)', 'Lowers high blood pressure and reduces fluid swelling.', 'Adults: 12.5-25mg once daily in the morning.', 'Passing urine more often, dizziness, low potassium, gout flare.', false, false, false, 'Yes'),
  ('Enalapril', 'Enalapril Maleate', 'Antihypertensive (ACE Inhibitor)', 'Treats high blood pressure and heart failure, and protects the kidneys in diabetes. Common brands in Kenya: Renitec.', 'Adults: usually 5-20mg once daily, up to 40mg/day.', 'Dry cough, dizziness, high potassium. Must not be taken in pregnancy.', false, false, false, 'Yes'),
  ('Losartan', 'Losartan Potassium', 'Antihypertensive', 'Treats high blood pressure and protects the kidneys in diabetes; used when enalapril causes a cough. Common brands in Kenya: Cozaar.', 'Adults: 50mg once daily, adjusted between 25-100mg.', 'Dizziness, high potassium. Must not be taken in pregnancy.', false, false, false, 'Yes'),
  ('Gliclazide', 'Gliclazide', 'Antidiabetic', 'Lowers blood sugar in type 2 diabetes, often with metformin. Can be used in chronic kidney disease. Common brands in Kenya: Diamicron.', 'Adults: standard tablets 40-80mg once daily with breakfast, up to 160mg twice daily. Modified-release: 30-120mg once daily with breakfast.', 'Low blood sugar (shaking, sweating, confusion), especially if meals are missed or with alcohol. Weight gain.', false, false, false, 'Yes'),
  ('Diclofenac', 'Diclofenac Sodium', 'NSAID / Anti-inflammatory', 'Relieves pain and inflammation in arthritis, back pain, sprains and period pain. Common brands in Kenya: Voltaren.', 'Adults: 50mg 2-3 times daily with food. Max 150mg/day.', 'Stomach pain, ulcers and bleeding, raised blood pressure, kidney strain.', false, false, false, 'Yes'),
  ('Hyoscine Butylbromide', 'Hyoscine Butylbromide', 'Antispasmodic', 'Relieves stomach cramps, irritable bowel spasms and period cramps. Common brands in Kenya: Buscopan.', 'Adults: 10-20mg up to 4 times daily.', 'Dry mouth, constipation, blurred vision, fast heartbeat.', false, false, false, 'No'),
  ('Fluconazole', 'Fluconazole', 'Antifungal', 'Treats vaginal thrush and other yeast infections, including oral thrush. Common brands in Kenya: Diflucan.', 'Vaginal thrush: 150mg as a single dose. Other infections as prescribed.', 'Nausea, headache, stomach pain.', false, false, false, 'Yes'),
  ('Clotrimazole', 'Clotrimazole', 'Antifungal', 'Cream for ringworm, athlete''s foot and skin thrush; pessary for vaginal thrush. Common brands in Kenya: Canesten.', 'Cream: apply 2-3 times daily, continuing 2 weeks after it clears. Pessary: 500mg at night as a single dose.', 'Mild burning or irritation where applied.', true, true, true, 'No'),
  ('Tenofovir/Lamivudine/Dolutegravir (TLD)', 'Tenofovir + Lamivudine + Dolutegravir', 'Antiretroviral', 'First-line HIV treatment in Kenya. Taken every day for life, it keeps the virus suppressed. Never stop or skip doses without talking to your HIV clinic.', 'One tablet once daily at the same time every day.', 'Headache, difficulty sleeping, weight gain.', true, false, true, 'Yes'),
  ('Levonorgestrel (Emergency Contraceptive)', 'Levonorgestrel', 'Contraceptive', 'Emergency contraception after unprotected sex. It is not an abortion pill and does not protect against HIV or other STIs. Common brands in Kenya: Postinor-2.', '1.5mg as a single dose as soon as possible, within 72 hours of unprotected sex.', 'Nausea, headache, irregular bleeding until the next period.', false, true, true, 'No')
) as v(name, generic_name, category, uses, dosage, side_effects, pregnancy_safe, alcohol_safe, lactation_safe, prescription_required)
where not exists (select 1 from public.drugs d where d.name = v.name);

-- Partial brand and generic names ("pana", "augm", "septr") should match as
-- the user types; full-text search only matches whole words. The table is
-- small, so the extra ilike terms cost nothing.
create or replace function public.search_drugs(q text)
returns setof public.drugs
language sql
stable
as $$
  select * from public.drugs
   where coalesce(trim(q), '') = ''
      or to_tsvector('english', name || ' ' || generic_name || ' ' || category || ' ' || uses)
         @@ plainto_tsquery('english', q)
      or name ilike '%' || q || '%'
      or generic_name ilike '%' || q || '%'
      or uses ilike '%' || q || '%'
   order by name;
$$;
