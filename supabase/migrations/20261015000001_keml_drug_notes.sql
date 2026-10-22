-- KEML 2023 notes on the two catalogue drugs it does not list as-is.
--
-- Section 26.1 lists no salbutamol-only inhaler: its reliever is salbutamol
-- + beclomethasone, in line with asthma guidance against relying on
-- salbutamol alone. Diclofenac is not listed at all. Both stay in the
-- catalogue, because people search for them, but now say so; the chat
-- function reads the same entries. Safe to re-run.

update public.drugs set uses = 'Quickly relieves wheezing and breathlessness in asthma and COPD. Common brands in Kenya: Ventolin. Kenya''s 2023 Essential Medicines List uses a combined salbutamol + beclomethasone inhaler instead; relying on salbutamol alone, without a preventer inhaler, is not recommended for ongoing asthma.' where name = 'Salbutamol Inhaler';
update public.drugs set uses = 'Relieves pain and inflammation in arthritis, back pain, sprains and period pain. Common brands in Kenya: Voltaren. Not on Kenya''s 2023 Essential Medicines List; ibuprofen is the listed alternative.' where name = 'Diclofenac';

insert into public.drugs (name, generic_name, category, uses, dosage, side_effects, pregnancy_safe, alcohol_safe, lactation_safe, prescription_required)
select 'Salbutamol/Beclomethasone Inhaler', 'Salbutamol + Beclomethasone', 'Bronchodilator / Corticosteroid', 'Relieves asthma symptoms while treating the airway inflammation behind them. The reliever inhaler on Kenya''s 2023 Essential Medicines List.', '100mcg salbutamol + 50mcg beclomethasone per puff. 1-2 puffs when needed for symptoms, as prescribed. Rinse the mouth after use.', 'Shaky hands, fast heartbeat, hoarse voice, oral thrush.', false, true, false, 'Yes'
where not exists (select 1 from public.drugs where name = 'Salbutamol/Beclomethasone Inhaler');
