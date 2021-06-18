--##############################################################################
--##############################################################################
--### 4CE Phase 1.2 and 2.2
--### Date: April 21, 2021 translated May 19, 2021
--### Database: Oracle
--### Data Model: i2b2
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--### Translated to Oracle: Michele Morris ( mim18@pitt.edu)
--##############################################################################
--##############################################################################

/*

INTRODUCTION:
This script contains code to generate both 4CE Phase 1.2 and Phase 2.2 files.
By default, it will only generate Phase 1.2 files, which contain obfuscated
aggregate counts and statistics. You need to change the settings in the
fource_config table so that it generates the Phase 2.2 files. Phase 2.2
files include non-obfuscated versions of all the Phase 1.1 files, as well as
files containing patient-level data.

PHASE 1.2 FILES:
This script creates the following Phase 1.2 files with obfuscated counts.
These files are uploaded to 4CE.
1) DailyCounts - Patient counts by calendar date
2) ClinicalCourse - Counts by number of days since hospital admission
3) AgeSex - Age and sex breakdowns
4) Labs - Lab values per day since admission
5) DiagProcMed - Diagnoses, procedures, and meds before and after admission
6) RaceByLocalCode - Breakdowns based on the codes used within your hospital
7) RaceBy4CECode - Breackdowns based on 4CE race categories
8) LabCodes - The laboratory code and unit mappings used (no patient data)

PHASE 2.2 FILES:
For Phase 2.2, the script creates a copy of Phase 1.2 tables 1-7 with "Local"
added to the beginning of the file name (e.g., LocalDailyCounts, LocalLabs, 
etc.). These tables contain counts that are not obfuscated. They should be
stored locally and not shared with 4CE. Phase 2.2 creates 5 additional files
that contain patient-level data. These should also be stored locally and not
shared with 4CE.
1) LocalPatientSummary - One row per patient in each cohort
2) LocalPatientClinicalCourse - Daily summary of patient hospitalizations
3) LocalPatientObservations - Each diagnosis, lab test, etc. per day
4) LocalPatientRace - Each patient's race code(s)
5) LocalPatientMapping - Map from i2b2 patient_num to ID used in the files

CONFIGURATION AND MAPPINGS:
You will need to modify the configuration and mapping tables at the beginning
of this script. Read the instructions carefully. You might also have to edit
the logic used in the queries to identify admissions, ICU visits, and deaths,
which are placed right after the code mappings.


OUTPUT OPTIONS:
For each Phase, the script provides three output options. The first option,
"output to columns" returns the data as tables to your query tool (e.g., SSMS).
The data are not saved to the database. This is useful if you want to copy the
data into a program like Excel. The second option, "output to CSV", returns
the data as tables with a single column that contains a CSV-style string. You
can copy and paste this into a text file and save it with a .csv extension. It
will then be in the correct format to upload to 4CE. The third option saves
the data as tables in your database. You need to specify a prefix, like
"dbo_FourCE_" that will be added to the begining of each table name.

COHORTS:
By default, this script only selects patients who had a positive COVID test
and were admitted. It partitions these patients into cohorts based on the 
quarter (2020 Q1, 2020 Q2, etc.) they were admitted. The configuration options
include_extra_cohorts_phase1 and include_extra_cohorts_phase2 will add extra
cohorts to the Phase 1.2 and/or Phase 2.2 files. These extra cohorts include
(1) patients who were admitted with a negative COVID test, (2) COVID positive
patients who were not admitted, (3) COVID negative patients who were not admitted,
and (4) patients with a U07.1 diagnoses (confirmed COVID), but no recorded 
positive COVID test. In other words, they capture every patient who had a COVID.
test. These extra cohorts are also partitioned by quarter. Note that for patients
who were not admitted, their first COVID test (pr U07.1 diagnosis) date is used 
as the "admission" date; and, "days_since_admission" is really days since the 
COVID test. Note that including these extra cohorts greatly increases the sizes
of the patient level Phase 2.2 files and makes the script take much longer run. 
(You can optionally define additional cohorts, based on custom inclusion or 
exclusion criteria, matching algorithms, or date range partitions.)

SOURCE DATA UPDATED DATE:
Use the configuration setting source_data_updated_date to indicate when the 
data that this script is run on was last updated. For example, if you are 
running this script on May 1, 2021, but the data has not been updated since
April 15, 2021, then set the source_data_updated_date to April 15. This is 
needed to determine the date beyond which data are censored. For example, if
a patient is still in the hospital on April 15, then the discharge date is 
unknown. (You can optionally assign a different source_data_updated_date to
each cohort. This would be needed if, for example, the data on COVID positive
patients are updated more frequently than COVID negative patients.)

ALTERNATIVE SCHEMAS AND MULTIPLE FACT TABLES:
The code assumes your fact and dimension tables are in the DBO schema. If
you use a different schema, then do a search-and-replace to change "dbo_" to
your schema. The code also assumes you have a single fact table called
"dbo_observation_fact". If you use multiple fact tables, then search for
"observation_fact" and change it as needed.

*/



--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--###
--### Configuration and code mappings (modify for your institution)
--###
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################

--##############################################################################
--### Set output csv file path
--### Global replace @exportFilePath with the path where you want your output 
--### files to land
--### Example replace @exportFilePath with C:\User\My4ceDir
--##############################################################################

--------------------------------------------------------------------------------
-- General settings
--------------------------------------------------------------------------------
--drop table fource_config; -- make sure everything is clean 
create table fource_config (
	siteid varchar(20), -- Up to 20 letters or numbers, must start with letter, no spaces or special characters.
	race_data_available int, -- 1 if your site collects race/ethnicity data; 0 if your site does not collect this.
	icu_data_available int, -- 1 if you have data on whether patients were in the ICU
	death_data_available int, -- 1 if you have data on whether patients have died
	code_prefix_icd9cm varchar(50), -- prefix (scheme) used in front of a ICD9CM diagnosis code; set to '' if not collected or no prefix used
	code_prefix_icd10cm varchar(50), -- prefix (scheme) used in front of a ICD10CM diagnosis code; set to '' if not collected or no prefix used
	source_data_updated_date date, -- the date your source data were last updated (e.g., '3/25/2021'); set to NULL if data go to the day you run this script
	-- Phase 1.2 (obfuscated aggregate data) options
	include_extra_cohorts_phase1 int, -- 0 by default, 1 to include COVID negative, U07.1, and non-admitted cohorts to Phase 1 files
	obfuscation_blur int, -- Add random number  || /-blur to each count (0 = no blur)
	obfuscation_small_count_mask int, -- Replace counts less than mask with -99 (0 = no small count masking)
	obfuscation_small_count_delete int, -- Delete rows where all values are small counts (0 = no, 1 = yes)
	obfuscation_agesex int, -- Replace combination of age-sex and total counts with -999 (0 = no, 1 = yes)
	output_phase1_as_columns int, -- Return the data in tables with separate columns per field
	output_phase1_as_csv int, -- Return the data in tables with a single column containing comma separated values
	save_phase1_as_columns int, -- Save the data as tables with separate columns per field
	save_phase1_as_prefix varchar(50), -- Table name prefix when saving the data as tables
	-- Phase 2.2 (non-obfuscated aggregate and patient level data) options
	include_extra_cohorts_phase2 int, -- 0 by default, 1 to include COVID negative, U07.1, and non-admitted cohorts to Phase 2 files
	replace_patient_num int, -- Replace the patient_num with a unique random number
	output_phase2_as_columns int, -- Return the data in tables with separate columns per field
	output_phase2_as_csv int, -- Return the data in tables with a single column containing comma separated values
	save_phase2_as_columns int, -- Save the data as tables with separate columns per field
	save_phase2_as_prefix varchar(50), -- Table name prefix when saving the data as tables
    	eval_start_date date -- use this so that dates can be changed consitently throughout the script
    --blackout_days_before -7 blackout_days_before 14 add these later
);
commit;

--truncate table fource_config;
insert into fource_config
	select 'UPitt', -- siteid
		1, -- race_data_available
		1, -- icu_data_available
		1, -- death_data_available
		'ICD9CM:', -- code_prefix_icd9cm
		'ICD10CM:', -- code_prefix_icd10cm
		NULL, -- source_data_updated_date
		-- Phase 1
		0, -- include_extra_cohorts_phase1 (please set to 1 if allowed by your IRB and institution)
		0, -- obfuscation_blur
		10, -- obfuscation_small_count_mask
		1, -- obfuscation_small_count_delete
		0, -- obfuscation_agesex
		0, -- output_phase1_as_columns
		1, -- output_phase1_as_csv
		0, -- save_phase1_as_columns
		'dbo_FourCE_', -- save_phase1_as_prefix (don't use "4CE" since it starts with a number)
		-- Phase 2
		0, -- include_extra_cohorts_phase2 (please set to 1 if allowed by your IRB and institution) 
		1, -- replace_patient_num 
		0, -- output_phase2_as_columns
		0, -- output_phase2_as_csv
		0, -- save_phase2_as_columns
		'dbo_FourCE_', -- save_phase2_as_prefix (don't use "4CE" since it starts with a number
        to_date('01-JAN-2019')
    from dual;
commit;

-- ! If your diagnosis codes do not start with a prefix (e.g., "ICD:"),
-- ! then you will need to customize queries the use the observation_fact table
-- ! so that only diagnoses are selected.


--------------------------------------------------------------------------------
-- Code mappings (excluding labs and meds)
-- * Don't change the "code" value.
-- * Modify the "local_code" to match your database.
-- * Repeat a code multiple times if you have more than one local code.
-- * Comment out rows that are not applicable to your database.
--------------------------------------------------------------------------------
--drop table fource_code_map;
create table fource_code_map (
	code varchar(50) not null,
	local_code varchar(50) not null
);

alter table fource_code_map add primary key (code, local_code);

-- Inpatient visit codes
-- * The SQL supports using either visit_dimension table or the observation_fact table.
-- * Change the code as needed. Comment out the versions that you do not use.
-- * You can replace this code with external mapping tables of location codes for example a list of hospital units 
insert into fource_code_map
	select '', ''  from dual where 1=0
	-- Inpatient visits (from the visit_dimension.inout_cd field)
	union all select 'inpatient_inout_cd', 'I' from dual
    union  all select 'inpatient_inout_cd', 'IN' from dual
	-- Inpatient visits (from the visit_dimension.location_cd field) 
    -- copy the line below for each code or location that represents an inpatient 
	union  all select 'inpatient_location_cd', 'Inpatient' from dual
	-- ICU visits (from the observation_fact.concept_cd field)
    -- copy the line below for each code or location that represents an inpatient 
	union  all select 'inpatient_concept_cd', 'UMLS:C1547137' from dual;-- from ACT ontology
commit;

-- ICU visit codes (optional)
-- * The SQL supports using either visit_dimension table or the observation_fact table.
-- * Change the code as needed. Comment out the versions that you do not use.
--truncate table fource_code_map;
insert into fource_code_map
	select '', '' from dual where 1=0
	-- ICU visits (from the visit_dimension.inout_cd field)
	union all select 'icu_inout_cd', 'ICU' from dual
	-- ICU visits (from the visit_dimension.location_cd field)
	union  all select 'icu_location_cd', 'ICU' from dual
	-- ICU visits (from the observation_fact.concept_cd field)
	union  all select 'icu_concept_cd', 'UMLS:C1547136' from dual-- from ACT ontology
   	union  all select 'icu_concept_cd', 'CPT4:99291' from dual-- from ACT ontology
	union  all select 'icu_concept_cd', 'CPT4:99292' from dual-- from ACT ontology
    -- ICU visits (from the observation_fact.location_cd field)
	union  all select 'icu_fact_location_cd', 'ICU' from dual
    -- ICU location_cd in observation_fact selected from external icu map
    union all select 'icu_fact_location_cd', icu_unit_code from external_icu_map;
--select * from fource_code_map;
commit;


-- If you use location_cd to map ICU  locations you can create a list here or load from an external mapping table
drop table fource_icu_location;
create table fource_icu_location as select cast(department_id as varchar2(50)) location_cd from icus;
--create table fource_icu_location as 
--select cast('icu1' as varchar2(50)) as location_cd from dual
--union
--select cast('icu1' as varchar2(50)) as location_cd from dual;
commit;

-- Sex codes
insert into fource_code_map
	select '', '' from dual where 1=0
	-- Sex (from the patient_dimension.sex_cd field)
	union all select 'sex_patient:male', 'M' from dual
	union  all select 'sex_patient:male', 'Male' from dual 
	union  all select 'sex_patient:female', 'F' from dual 
	union  all select 'sex_patient:female', 'Female' from dual 
	-- Sex (from the observation_fact.concept_cd field)
	union  all select 'sex_fact:male', 'DEM|SEX:M' from dual 
	union  all select 'sex_fact:male', 'DEM|SEX:Male' from dual 
	union  all select 'sex_fact:female', 'DEM|SEX:F' from dual 
	union  all select 'sex_fact:female', 'DEM|SEX:Female' from dual; 

-- Race codes (use the code set for your country, comment out other countries)
insert into fource_code_map
	select '', '' from dual where 1=0
	-------------------------------------------------------------------
	-- Race: United States
	-------------------------------------------------------------------
	-- Race (from the patient _dimension.race_cd field)
	union all select 'race_patient:american_indian', 'NA' 
	from dual union  all select 'race_patient:asian', 'A' 
	from dual union  all select 'race_patient:asian', 'AS' 
	from dual union  all select 'race_patient:black', 'B' 
	from dual union  all select 'race_patient:hawaiian_pacific_islander', 'H' 
	from dual union  all select 'race_patient:hawaiian_pacific_islander', 'P' 
	from dual union  all select 'race_patient:white', 'W' 
	from dual union  all select 'race_patient:hispanic_latino', 'HL' 
	from dual union  all select 'race_patient:other', 'O' -- include multiple if no additional information is known
	from dual union  all select 'race_patient:no_information', 'NI'  -- unknown, not available, missing, refused to answer, not recorded, etc.
	-- Race (from the observation_fact.concept_cd field)
	from dual union  all select 'race_fact:american_indian', 'DEM|race:NA' 
	from dual union  all select 'race_fact:asian', 'DEM|race:A' 
	from dual union  all select 'race_fact:asian', 'DEM|race:AS' 
	from dual union  all select 'race_fact:black', 'DEM|race:B' 
	from dual union  all select 'race_fact:hawaiian_pacific_islander', 'DEM|race:H' 
	from dual union  all select 'race_fact:hawaiian_pacific_islander', 'DEM|race:P' 
	from dual union  all select 'race_fact:white', 'DEM|race:W' 
	from dual union  all select 'race_fact:hispanic_latino', 'DEM|HISP:Y' 
	from dual union  all select 'race_fact:hispanic_latino', 'DEM|HISPANIC:Y' 
	from dual union  all select 'race_fact:other', 'DEM|race:O'  -- include multiple if no additional information is known
	from dual union  all select 'race_fact:no_information', 'DEM|race:NI' from dual; -- unknown, not available, missing, refused to answer, not recorded, etc.
	-------------------------------------------------------------------
	-- Race: United Kingdom (Ethnicity)
	-------------------------------------------------------------------
	-- Ethnicity (from the patient_dimension.race_cd field)
	-- from dual union  all select 'race_patient:uk_asian', 'Asian' -- Asian or Asian British (Indian, Pakistani, Bangladeshi, Chinese, other Asian background) 
	-- from dual union  all select 'race_patient:uk_black', 'Black' -- Black, African, Carribean, or Black British (African/ Caribbean/ any other Black, African or Caribbean background)
	-- from dual union  all select 'race_patient:uk_white', 'White' -- White (English/ Welsh/ Scottish/Northern Irish/ British, Irish, Gypsy or Irish Traveller, other White background)
	-- from dual union  all select 'race_patient:uk_multiple', 'Multiple' -- Mixed or Multiple ethnic groups (White and Black Caribbean, White and Black African, White and Asian, Any other Mixed or Multiple ethnic background)
	-- from dual union  all select 'race_patient:uk_other', 'Other' -- Other ethnic group (Arab, other ethnic group)
	-- from dual union  all select 'race_patient:uk_no_information', 'NI' -- unknown, not available, missing, refused to answer, not recorded, etc.
	-------------------------------------------------------------------
	-- Race: Singapore
	-------------------------------------------------------------------
	-- Race (from the patient_dimension.race_cd field)
	-- from dual union  all select 'race_patient:singapore_chinese', 'Chinese'
	-- from dual union  all select 'race_patient:singapore_malay', 'Malay'
	-- from dual union  all select 'race_patient:singapore_indian', 'Indian'
	-- from dual union  all select 'race_patient:singapore_other', 'Other'
	-- from dual union  all select 'race_patient:singapore_no_information', 'NI' -- unknown, not available, missing, refused to answer, not recorded, etc.
	-------------------------------------------------------------------
	-- Race: Brazil
	-------------------------------------------------------------------
	-- Race (from the patient_dimension.race_cd field)
	-- from dual union  all select 'race_patient:brazil_branco', 'Branco'
	-- from dual union  all select 'race_patient:brazil_pardo', 'Pardo'
	-- from dual union  all select 'race_patient:brazil_preto', 'Preto'
	-- from dual union  all select 'race_patient:brazil_indigena', 'Indigena'
	-- from dual union  all select 'race_patient:brazil_amarelo', 'Amarelo'
	-- from dual union  all select 'race_patient:brazil_no_information', 'NI' -- unknown, not available, missing, refused to answer, not recorded, etc.

-- Codes that indicate a COVID-19 nucleic acid test result (use option #1 and/or option #2)
-- COVID-19 Test Option #1: individual concept_cd values

insert into fource_code_map
	select 'covidpos', 'LAB|LOINC:COVID19POS' from dual
	union all
	select 'covidneg', 'LAB|LOINC:COVID19NEG' from dual;
    
-- COVID-19 Test Option #2: an ontology path (e.g., COVID ACT "Any Positive Test" path)
insert into fource_code_map
	select distinct 'covidpos', concept_cd
		from @crcSchema.concept_dimension c 
		where concept_path like '\ACT\UMLS_C0031437\SNOMED_3947185011\UMLS_C0022885\UMLS_C1335447\%'
			and concept_cd is not null
			and not exists (select * from fource_code_map m where m.code='covidpos' and m.local_code=c.concept_cd)
	union all
	select distinct 'covidneg', concept_cd
		from @crcSchema.concept_dimension c
		where concept_path like '\ACT\UMLS_C0031437\SNOMED_3947185011\UMLS_C0022885\UMLS_C1334932\%'
			and concept_cd is not null
			and not exists (select * from fource_code_map m where m.code='covidneg' and m.local_code=c.concept_cd);
-- Other codes that indicate confirmed COVID-19 (e.g., ICD-10 code U07.1, but not U07.2 or U07.3)
insert into fource_code_map
	select 'covidU071', code_prefix_icd10cm || 'U07.1'
		from fource_config
	union all
	select 'covidU071', code_prefix_icd10cm || 'U071' --place holder
		from fource_config;
commit;
--------------------------------------------------------------------------------
-- Lab mappings
-- * Do not change the fource_* columns.
-- * Modify the local_* columns to match how your lab data are represented.
-- * Add another row for a lab if you use multiple codes (e.g., see PaCO2).
-- * Delete a row if you don't have that lab.
-- * Change the scale_factor if you use different units.
-- * The lab value will be multiplied by the scale_factor
-- *   to convert from your units to the 4CE units.
-- * Add another row if the same code can have multiple units (e.g., see PaO2).
-- * Set local_lab_units='DEFAULT' to match labs with '' or NULL units 
-- *   (e.g., see PaO2). Only use this if you are sure what the units are.
-- *   Add what you think the true units are to the end of the local_lab_name.
--------------------------------------------------------------------------------
--DROP TABLE fource_lab_map;
create table fource_lab_map (
	fource_loinc varchar(20) not null, 
	fource_lab_units varchar(20) not null, 
	fource_lab_name varchar(100) not null,
	scale_factor float not null, 
	local_lab_code varchar(50) not null, 
	local_lab_units varchar(20) not null, 
	local_lab_name varchar(500) not null
);

alter table fource_lab_map add primary key (fource_loinc, local_lab_code, local_lab_units);
insert into fource_lab_map
	select fource_loinc, fource_lab_units, fource_lab_name,
		scale_factor,
		'LOINC:' || local_lab_code,  -- Change "LOINC:" to your local LOINC code prefix (scheme)
		local_lab_units, local_lab_name
	from (
		select null fource_loinc, null fource_lab_units, null fource_lab_name, 
				null scale_factor, null local_lab_code, null local_lab_units, null local_lab_name from dual
			where 1=0
		union select '1742-6', 'U/L', 'alanine aminotransferase (ALT)', 1, '1742-6', 'U/L', 'YourLocalLabName' 
		from dual union select '1751-7', 'g/dL', 'albumin', 1, '1751-7', 'g/dL', 'YourLocalLabName' 
		from dual union  select '1920-8', 'U/L', 'aspartate aminotransferase (AST)', 1, '1920-8', 'U/L', 'YourLocalLabName' 
		from dual union  select '1975-2', 'mg/dL', 'total bilirubin', 1, '1975-2', 'mg/dL', 'YourLocalLabName' 
		from dual union  select '1988-5', 'mg/L', 'C-reactive protein (CRP) (Normal Sensitivity)', 1, '1988-5', 'mg/L', 'YourLocalLabName' 
		from dual union  select '2019-8', 'mmHg', 'PaCO2', 1, '2019-8', 'mmHg', 'YourLocalLabName' 
		from dual union  select '2160-0', 'mg/dL', 'creatinine', 1, '2160-0', 'mg/dL', 'YourLocalLabName' 
		from dual union  select '2276-4', 'ng/mL', 'Ferritin', 1, '2276-4', 'ng/mL', 'YourLocalLabName' 
		from dual union  select '2532-0', 'U/L', 'lactate dehydrogenase (LDH)', 1, '2532-0', 'U/L', 'YourLocalLabName' 
		from dual union  select '2703-7', 'mmHg', 'PaO2', 1, '2703-7', 'mmHg', 'YourLocalLabName' 
		from dual union  select '3255-7', 'mg/dL', 'Fibrinogen', 1, '3255-7', 'mg/dL', 'YourLocalLabName' 
		from dual union  select '33959-8', 'ng/mL', 'procalcitonin', 1, '33959-8', 'ng/mL', 'YourLocalLabName' 
		from dual union  select '48065-7', 'ng/mL{FEU}', 'D-dimer (FEU)', 1, '48065-7', 'ng/mL{FEU}', 'YourLocalLabName' 
		from dual union  select '48066-5', 'ng/mL{DDU}', 'D-dimer (DDU)', 1, '48066-5', 'ng/mL{DDU}', 'YourLocalLabName' 
		from dual union  select '49563-0', 'ng/mL', 'cardiac troponin (High Sensitivity)', 1, '49563-0', 'ng/mL', 'YourLocalLabName' 
		from dual union  select '6598-7', 'ug/L', 'cardiac troponin (Normal Sensitivity)', 1, '6598-7', 'ug/L', 'YourLocalLabName' 
		from dual union  select '5902-2', 's', 'prothrombin time (PT)', 1, '5902-2', 's', 'YourLocalLabName' 
		from dual union  select '6690-2', '10*3/uL', 'white blood cell count (Leukocytes)', 1, '6690-2', '10*3/uL', 'YourLocalLabName' 
		from dual union  select '731-0', '10*3/uL', 'lymphocyte count', 1, '731-0', '10*3/uL', 'YourLocalLabName'
		from dual union select '751-8', '10*3/uL', 'neutrophil count', 1, '751-8', '10*3/uL', 'YourLocalLabName'
		from dual union select '777-3', '10*3/uL', 'platelet count', 1, '777-3', '10*3/uL', 'YourLocalLabName'
		from dual union select '34714-6', 'DEFAULT', 'INR', 1, '34714-6', 'DEFAULT', 'YourLocalLabName' from dual

		--Example of listing an additional code for the same lab
		--from dual union select '2019-8', 'mmHg', 'PaCO2', 1, 'LAB:PaCO2', 'mmHg', 'Carbon dioxide partial pressure in arterial blood'
		--Examples of listing different units for the same lab
		--from dual union select '2703-7', 'mmHg', 'PaO2', 10, '2703-7', 'cmHg', 'PaO2'
		--from dual union select '2703-7', 'mmHg', 'PaO2', 25.4, '2703-7', 'inHg', 'PaO2'
		--This will use the given scale factor (in this case 1) for any lab with NULL or empty string units 
		--from dual union select '2703-7', 'mmHg', 'PaO2', 1, '2703-7', 'DEFAULT', 'PaO2 [mmHg]'
	) t;
commit;

-- Use the concept_dimension table to get an expanded list of local lab codes (optional).
-- This will find paths corresponding to concepts already in the fource_lab_map table,
-- and then find all the concepts corresponding to child paths. Make sure you update the
-- scale_factor, local_lab_units, and local_lab_name as needed.
-- WARNING: This query might take several minutes to run.
-- ****THIS IS UNTESTED*****
/*
insert into fource_lab_map
	select distinct l.fource_loinc, l.fource_lab_units, l.fource_lab_name, l.scale_factor, d.concept_cd, l.local_lab_units, l.local_lab_name
	from fource_lab_map l
		inner join @crcSchema.concept_dimension c
			on l.local_lab_code = c.concept_cd
		inner join @crcSchema.concept_dimension d
			on d.concept_path like c.concept_path || '%'
	where not exists (
		select *
		from fource_lab_map t
		where t.fource_loinc = l.fource_loinc and t.local_lab_code = d.concept_cd
	)
*/

-- Use the concept_dimension table to get the local names for labs (optional).
/*
update l
	set l.local_lab_name = c.name_char
	from fource_lab_map l
		inner join @crcSchema.concept_dimension c
			on l.local_lab_code = c.concept_cd
*/

--------------------------------------------------------------------------------
-- Lab mappings report (for debugging lab mappings)
--------------------------------------------------------------------------------
-- Get a list of all the codes and units in the data for 4CE labs since 1/1/2019
create table fource_lab_units_facts (
	fact_code varchar(50) not null,
	fact_units varchar(50),
	num_facts int,
	mean_value numeric(18,5),
	stddev_value numeric(18,5)
); 

--188s
create index fource_lap_map_ndx on fource_lab_map(local_lab_code);
insert into fource_lab_units_facts
select * from (
with labs_in_period as (
select concept_cd, units_cd, nval_num
	from @crcSchema.observation_fact f
    join fource_lab_map m  on m.local_lab_code = f.concept_cd 
	where trunc(start_date) >= (select trunc(start_date) from fource_config where rownum = 1)
)
select concept_cd, units_cd, count(*) num_facts, avg(nval_num) avg_val, stddev(nval_num) stddev_val
from labs_in_period
group by concept_cd, units_cd);
commit;
--select * from fource_lab_units_facts;
/*
insert into fource_lab_units_facts
	select concept_cd, units_cd, count(*), avg(nval_num), stddev(nval_num)
	from @crcSchema.observation_fact f
    join fource_lab_map m  on m.local_lab_code = f.concept_cd 
	where trunc(start_date) >= (select trunc(start_date) from fource_config where rownum = 1)
	group by concept_cd, units_cd;
*/    


-- Create a table that stores a report about local lab units
--drop table fource_lab_map_report;
create table fource_lab_map_report (
	fource_loinc varchar(20) not null, 
	fource_lab_units varchar(20), 
	fource_lab_name varchar(100),
	scale_factor float, 
	local_lab_code varchar(50) not null, 
	local_lab_units varchar(20) not null, 
	local_lab_name varchar(500),
	num_facts int,
	mean_value numeric(18,5),
	stddev_value numeric(18,5),
	notes varchar(1000)
)
; 
alter table fource_lab_map_report add primary key (fource_loinc, local_lab_code, local_lab_units);
-- Compare the fource_lab_map table to the codes and units in the data


insert into fource_lab_map_report
	select 
		nvl(m.fource_loinc,a.fource_loinc) fource_loinc,
		nvl(m.fource_lab_units,a.fource_lab_units) fource_lab_units,
		nvl(m.fource_lab_name,a.fource_lab_name) fource_lab_name,
		nvl(m.scale_factor,0) scale_factor,
		nvl(m.local_lab_code,f.fact_code) local_lab_code,
		coalesce(m.local_lab_units,f.fact_units,'((null))') local_lab_units,
		nvl(m.local_lab_name,'((missing))') local_lab_name,
		nvl(f.num_facts,0) num_facts,
		nvl(f.mean_value,-999) mean_value,
		nvl(f.stddev_value,-999) stddev_value,
		(case when scale_factor is not null and num_facts is not null then 'GOOD: Code and units found in the data'
			when m.fource_loinc is not null and c.fact_code is null then 'WARNING: This code from the lab mappings table could not be found in the data -- double check if you use another loinc or local code' 
			when scale_factor is not null then 'WARNING: These local_lab_units in the lab mappings table could not be found in the data '
			else 'WARNING: These local_lab_units exist in the data but are missing from the lab mappings table -- map to the 4CE units using scale factor'
			end) notes
	from fource_lab_map m
		full outer join fource_lab_units_facts f
			on f.fact_code=m.local_lab_code and nvl(nullif(f.fact_units,''),'DEFAULT')=m.local_lab_units
		left outer join (
			select distinct fource_loinc, fource_lab_units, fource_lab_name, local_lab_code
			from fource_lab_map
		) a on a.local_lab_code=f.fact_code
		left outer join (
			select distinct fact_code from fource_lab_units_facts
		) c on m.local_lab_code=c.fact_code;
commit;
--select * from fource_lab_map_report;

-- View the results, including counts, to help you check your mappings (optional)
/*
select * from fource_lab_map_report order by fource_loinc, num_facts desc
*/

--------------------------------------------------------------------------------
-- Medication mappings
-- * Do not change the med_class or add additional medications.
-- * The ATC and RxNorm codes represent the same list of medications.
-- * Use ATC and/or RxNorm, depending on what your institution uses.
--------------------------------------------------------------------------------
--drop table fource_med_map;
create table fource_med_map (
	med_class varchar(50) not null,
	code_type varchar(10) not null,
	local_med_code varchar(50) not null
)
; 
alter table fource_med_map add primary key (med_class, code_type, local_med_code);

-- ATC codes (optional)
insert into fource_med_map
	select m, 'ATC' t, 'ATC:' || c  -- Change "ATC:" to your local ATC code prefix (scheme)
	from (
		-- Don't add or remove drugs
		select 'ACEI' m, c from (select 'C09AA01' c from dual union select 'C09AA02' from dual union select 'C09AA03' from dual 
            union select 'C09AA04' from dual union select 'C09AA05' from dual union select 'C09AA06' from dual union select 'C09AA07' from dual 
            union select 'C09AA08' from dual union select 'C09AA09' from dual union select 'C09AA10' from dual union select 'C09AA11' from dual 
            union select 'C09AA13' from dual union select 'C09AA15' from dual union select 'C09AA16' from dual) t
		union 
        select 'ARB', c from (select 'C09CA01' c from dual union select 'C09CA02' from dual union select 'C09CA03' from dual 
            union select 'C09CA04' from dual union select 'C09CA06' from dual union select 'C09CA07' from dual 
            union select 'C09CA08' from dual) t
		union 
        select 'COAGA', c from (select 'B01AC04' c from dual union select 'B01AC05' from dual union select 'B01AC07' from dual 
            union select 'B01AC10' from dual union select 'B01AC13' from dual union select 'B01AC16' from dual 
            union select 'B01AC17' from dual union select 'B01AC22' from dual union select 'B01AC24' from dual 
            union select 'B01AC25' from dual union select 'B01AC26' from dual) t
		union 
        select 'COAGB', c from (select 'B01AA01' c from dual union select 'B01AA03' from dual 
            union select 'B01AA04' from dual union select 'B01AA07' from dual 
            union select 'B01AA11' from dual union select 'B01AB01' from dual 
            union select 'B01AB04' from dual union select 'B01AB05' from dual 
            union select 'B01AB06' from dual union select 'B01AB07' from dual 
            union select 'B01AB08' from dual union select 'B01AB10' from dual 
            union select 'B01AB12' from dual union select 'B01AE01' from dual 
            union select 'B01AE02' from dual union select 'B01AE03' from dual 
            union select 'B01AE06' from dual union select 'B01AE07' from dual 
            union select 'B01AF01' from dual union select 'B01AF02' from dual 
            union select 'B01AF03' from dual union select 'B01AF04' from dual 
            union select 'B01AX05' from dual union select 'B01AX07' from dual) t
		union 
        select 'COVIDVIRAL', c from (select 'J05AE10' c from dual union select 'J05AP01' from dual union select 'J05AR10' from dual) t
		union 
        select 'DIURETIC', c from (select 'C03CA01' c from dual union select 'C03CA02' from dual 
            union select 'C03CA03' from dual union select 'C03CA04' from dual 
            union select 'C03CB01' from dual union select 'C03CB02' from dual union select 'C03CC01' from dual) t
        union 
        select 'HCQ', c from (select 'P01BA01' c from dual union select 'P01BA02' from dual) t
		union 
        select 'ILI', c from (select 'L04AC03' c from dual union select 'L04AC07' from dual 
            union select 'L04AC11' from dual union select 'L04AC14' from dual) t
		union 
        select 'INTERFERON', c from (select 'L03AB08' c from dual union select 'L03AB11' from dual) t
		union 
        select 'SIANES', c from (select 'M03AC03' c from dual union select 'M03AC09' from dual 
            union select 'M03AC11' from dual union select 'N01AX03' from dual 
            union select 'N01AX10' from dual union select 'N05CD08' from dual union select 'N05CM18' from dual) t
		union 
        select 'SICARDIAC', c from (select 'B01AC09' c from dual union select 'C01CA03' from dual 
            union select 'C01CA04' from dual union select 'C01CA06' from dual union select 'C01CA07' from dual 
            union select 'C01CA24' from dual union select 'C01CE02' from dual union select 'C01CX09' from dual 
            union select 'H01BA01' from dual union select 'R07AX01' from dual) t
	) t;
commit;

-- RxNorm codes (optional)
insert into fource_med_map
	select m, 'RxNorm' t, 'RXNORM:' || c  -- Change "RxNorm:" to your local RxNorm code prefix (scheme)
	from (
		-- Don't add or remove drugs
    select 'ACEI' m, c from 
    (select '36908' c from dual
	union select '39990' from dual
	union select '104375' from dual
	union select '104376' from dual
	union select '104377' from dual
	union select '104378' from dual
	union select '104383' from dual
	union select '104384' from dual
	union select '104385' from dual
	union select '1299896' from dual
	union select '1299897' from dual
	union select '1299963' from dual
	union select '1299965' from dual
	union select '1435623' from dual
	union select '1435624' from dual
	union select '1435630' from dual
	union select '1806883' from dual
	union select '1806884' from dual
	union select '1806890' from dual
	union select '18867' from dual
	union select '197884' from dual
	union select '198187' from dual
	union select '198188' from dual
	union select '198189' from dual
	union select '199351' from dual
	union select '199352' from dual
	union select '199353' from dual
	union select '199622' from dual
	union select '199707' from dual
	union select '199708' from dual
	union select '199709' from dual
	union select '1998' from dual
	union select '199816' from dual
	union select '199817' from dual
	union select '199931' from dual
	union select '199937' from dual
	union select '205326' from dual
	union select '205707' from dual
	union select '205778' from dual
	union select '205779' from dual
	union select '205780' from dual
	union select '205781' from dual
	union select '206277' from dual
	union select '206313' from dual
	union select '206764' from dual
	union select '206765' from dual
	union select '206766' from dual
	union select '206771' from dual
	union select '207780' from dual
	union select '207792' from dual
	union select '207800' from dual
	union select '207820' from dual
	union select '207891' from dual
	union select '207892' from dual
	union select '207893' from dual
	union select '207895' from dual
	union select '210671' from dual
	union select '210672' from dual
	union select '210673' from dual
	union select '21102' from dual
	union select '211535' from dual
	union select '213482' from dual
	union select '247516' from dual
	union select '251856' from dual
	union select '251857' from dual
	union select '260333' from dual
	union select '261257' from dual
	union select '261258' from dual
	union select '261962' from dual
	union select '262076' from dual
	union select '29046' from dual
	union select '30131' from dual
	union select '308607' from dual
	union select '308609' from dual
	union select '308612' from dual
	union select '308613' from dual
	union select '308962' from dual
	union select '308963' from dual
	union select '308964' from dual
	union select '310063' from dual
	union select '310065' from dual
	union select '310066' from dual
	union select '310067' from dual
	union select '310422' from dual
	union select '311353' from dual
	union select '311354' from dual
	union select '311734' from dual
	union select '311735' from dual
	union select '312311' from dual
	union select '312312' from dual
	union select '312313' from dual
	union select '312748' from dual
	union select '312749' from dual
	union select '312750' from dual
	union select '313982' from dual
	union select '313987' from dual
	union select '314076' from dual
	union select '314077' from dual
	union select '314203' from dual
	union select '317173' from dual
	union select '346568' from dual
	union select '347739' from dual
	union select '347972' from dual
	union select '348000' from dual
	union select '35208' from dual
	union select '35296' from dual
	union select '371001' from dual
	union select '371254' from dual
	union select '371506' from dual
	union select '372007' from dual
	union select '372274' from dual
	union select '372614' from dual
	union select '372945' from dual
	union select '373293' from dual
	union select '373731' from dual
	union select '373748' from dual
	union select '373749' from dual
	union select '374176' from dual
	union select '374177' from dual
	union select '374938' from dual
	union select '378288' from dual
	union select '3827' from dual
	union select '38454' from dual
	union select '389182' from dual
	union select '389183' from dual
	union select '389184' from dual
	union select '393442' from dual
	union select '401965' from dual
	union select '401968' from dual
	union select '411434' from dual
	union select '50166' from dual
	union select '542702' from dual
	union select '542704' from dual
	union select '54552' from dual
	union select '60245' from dual
	union select '629055' from dual
	union select '656757' from dual
	union select '807349' from dual
	union select '845488' from dual
	union select '845489' from dual
	union select '854925' from dual
	union select '854927' from dual
	union select '854984' from dual
	union select '854986' from dual
	union select '854988' from dual
	union select '854990' from dual
	union select '857169' from dual
	union select '857171' from dual
	union select '857183' from dual
	union select '857187' from dual
	union select '857189' from dual
	union select '858804' from dual
	union select '858806' from dual
	union select '858810' from dual
	union select '858812' from dual
	union select '858813' from dual
	union select '858815' from dual
	union select '858817' from dual
	union select '858819' from dual
	union select '858821' from dual
	union select '898687' from dual
	union select '898689' from dual
	union select '898690' from dual
	union select '898692' from dual
	union select '898719' from dual
	union select '898721' from dual
	union select '898723' from dual
	union select '898725' from dual) t
union select 'ARB' m, c from
	(select '118463' c from dual
	union select '108725' from dual
	union select '153077' from dual
	union select '153665' from dual
	union select '153666' from dual
	union select '153667' from dual
	union select '153821' from dual
	union select '153822' from dual
	union select '153823' from dual
	union select '153824' from dual
	union select '1996253' from dual
	union select '1996254' from dual
	union select '199850' from dual
	union select '199919' from dual
	union select '200094' from dual
	union select '200095' from dual
	union select '200096' from dual
	union select '205279' from dual
	union select '205304' from dual
	union select '205305' from dual
	union select '2057151' from dual
	union select '2057152' from dual
	union select '2057158' from dual
	union select '206256' from dual
	union select '213431' from dual
	union select '213432' from dual
	union select '214354' from dual
	union select '261209' from dual
	union select '261301' from dual
	union select '282755' from dual
	union select '284531' from dual
	union select '310139' from dual
	union select '310140' from dual
	union select '311379' from dual
	union select '311380' from dual
	union select '314073' from dual
	union select '349199' from dual
	union select '349200' from dual
	union select '349201' from dual
	union select '349483' from dual
	union select '351761' from dual
	union select '351762' from dual
	union select '352001' from dual
	union select '352274' from dual
	union select '370704' from dual
	union select '371247' from dual
	union select '372651' from dual
	union select '374024' from dual
	union select '374279' from dual
	union select '374612' from dual
	union select '378276' from dual
	union select '389185' from dual
	union select '484824' from dual
	union select '484828' from dual
	union select '484855' from dual
	union select '52175' from dual
	union select '577776' from dual
	union select '577785' from dual
	union select '577787' from dual
	union select '598024' from dual
	union select '615856' from dual
	union select '639536' from dual
	union select '639537' from dual
	union select '639539' from dual
	union select '639543' from dual
	union select '69749' from dual
	union select '73494' from dual
	union select '83515' from dual
	union select '83818' from dual
	union select '979480' from dual
	union select '979482' from dual
	union select '979485' from dual
	union select '979487' from dual
	union select '979492' from dual
	union select '979494' from dual) t
union select 'COAGA' m, c from
	(select '27518' c from dual
	union select '10594' from dual
	union select '108911' from dual
	union select '1116632' from dual
	union select '1116634' from dual
	union select '1116635' from dual
	union select '1116639' from dual
	union select '1537034' from dual
	union select '1537038' from dual
	union select '1537039' from dual
	union select '1537045' from dual
	union select '1656052' from dual
	union select '1656055' from dual
	union select '1656056' from dual
	union select '1656061' from dual
	union select '1656683' from dual
	union select '1666332' from dual
	union select '1666334' from dual
	union select '1736469' from dual
	union select '1736470' from dual
	union select '1736472' from dual
	union select '1736477' from dual
	union select '1736478' from dual
	union select '1737465' from dual
	union select '1737466' from dual
	union select '1737468' from dual
	union select '1737471' from dual
	union select '1737472' from dual
	union select '1812189' from dual
	union select '1813035' from dual
	union select '1813037' from dual
	union select '197622' from dual
	union select '199314' from dual
	union select '200348' from dual
	union select '200349' from dual
	union select '205253' from dual
	union select '206714' from dual
	union select '207569' from dual
	union select '208316' from dual
	union select '208558' from dual
	union select '213169' from dual
	union select '213299' from dual
	union select '241162' from dual
	union select '261096' from dual
	union select '261097' from dual
	union select '309362' from dual
	union select '309952' from dual
	union select '309953' from dual
	union select '309955' from dual
	union select '313406' from dual
	union select '32968' from dual
	union select '333833' from dual
	union select '3521' from dual
	union select '371917' from dual
	union select '374131' from dual
	union select '374583' from dual
	union select '375035' from dual
	union select '392451' from dual
	union select '393522' from dual
	union select '613391' from dual
	union select '73137' from dual
	union select '749196' from dual
	union select '749198' from dual
	union select '75635' from dual
	union select '83929' from dual
	union select '855811' from dual
	union select '855812' from dual
	union select '855816' from dual
	union select '855818' from dual
	union select '855820' from dual) t
union select 'COAGB' m, c from
      	(select '2110605' c from dual
	union select '237057' from dual
	union select '69528' from dual
	union select '8150' from dual
	union select '163426' from dual
	union select '1037042' from dual
	union select '1037044' from dual
	union select '1037045' from dual
	union select '1037049' from dual
	union select '1037179' from dual
	union select '1037181' from dual
	union select '1110708' from dual
	union select '1114195' from dual
	union select '1114197' from dual
	union select '1114198' from dual
	union select '1114202' from dual
	union select '11289' from dual
	union select '114934' from dual
	union select '1232082' from dual
	union select '1232084' from dual
	union select '1232086' from dual
	union select '1232088' from dual
	union select '1241815' from dual
	union select '1241823' from dual
	union select '1245458' from dual
	union select '1245688' from dual
	union select '1313142' from dual
	union select '1359733' from dual
	union select '1359900' from dual
	union select '1359967' from dual
	union select '1360012' from dual
	union select '1360432' from dual
	union select '1361029' from dual
	union select '1361038' from dual
	union select '1361048' from dual
	union select '1361226' from dual
	union select '1361568' from dual
	union select '1361574' from dual
	union select '1361577' from dual
	union select '1361607' from dual
	union select '1361613' from dual
	union select '1361615' from dual
	union select '1361853' from dual
	union select '1362024' from dual
	union select '1362026' from dual
	union select '1362027' from dual
	union select '1362029' from dual
	union select '1362030' from dual
	union select '1362048' from dual
	union select '1362052' from dual
	union select '1362054' from dual
	union select '1362055' from dual
	union select '1362057' from dual
	union select '1362059' from dual
	union select '1362060' from dual
	union select '1362061' from dual
	union select '1362062' from dual
	union select '1362063' from dual
	union select '1362065' from dual
	union select '1362067' from dual
	union select '1362824' from dual
	union select '1362831' from dual
	union select '1362837' from dual
	union select '1362935' from dual
	union select '1362962' from dual
	union select '1364430' from dual
	union select '1364434' from dual
	union select '1364435' from dual
	union select '1364441' from dual
	union select '1364445' from dual
	union select '1364447' from dual
	union select '1490491' from dual
	union select '1490493' from dual
	union select '15202' from dual
	union select '152604' from dual
	union select '154' from dual
	union select '1549682' from dual
	union select '1549683' from dual
	union select '1598' from dual
	union select '1599538' from dual
	union select '1599542' from dual
	union select '1599543' from dual
	union select '1599549' from dual
	union select '1599551' from dual
	union select '1599553' from dual
	union select '1599555' from dual
	union select '1599557' from dual
	union select '1656595' from dual
	union select '1656599' from dual
	union select '1656760' from dual
	union select '1657991' from dual
	union select '1658634' from dual
	union select '1658637' from dual
	union select '1658647' from dual
	union select '1658659' from dual
	union select '1658690' from dual
	union select '1658692' from dual
	union select '1658707' from dual
	union select '1658717' from dual
	union select '1658719' from dual
	union select '1658720' from dual
	union select '1659195' from dual
	union select '1659197' from dual
	union select '1659260' from dual
	union select '1659263' from dual
	union select '1723476' from dual
	union select '1723478' from dual
	union select '1798389' from dual
	union select '1804730' from dual
	union select '1804735' from dual
	union select '1804737' from dual
	union select '1804738' from dual
	union select '1807809' from dual
	union select '1856275' from dual
	union select '1856278' from dual
	union select '1857598' from dual
	union select '1857949' from dual
	union select '1927851' from dual
	union select '1927855' from dual
	union select '1927856' from dual
	union select '1927862' from dual
	union select '1927864' from dual
	union select '1927866' from dual
	union select '197597' from dual
	union select '198349' from dual
	union select '1992427' from dual
	union select '1992428' from dual
	union select '1997015' from dual
	union select '1997017' from dual
	union select '204429' from dual
	union select '204431' from dual
	union select '205791' from dual
	union select '2059015' from dual
	union select '2059017' from dual
	union select '209081' from dual
	union select '209082' from dual
	union select '209083' from dual
	union select '209084' from dual
	union select '209086' from dual
	union select '209087' from dual
	union select '209088' from dual
	union select '211763' from dual
	union select '212123' from dual
	union select '212124' from dual
	union select '212155' from dual
	union select '238722' from dual
	union select '238727' from dual
	union select '238729' from dual
	union select '238730' from dual
	union select '241112' from dual
	union select '241113' from dual
	union select '242501' from dual
	union select '244230' from dual
	union select '244231' from dual
	union select '244239' from dual
	union select '244240' from dual
	union select '246018' from dual
	union select '246019' from dual
	union select '248140' from dual
	union select '248141' from dual
	union select '251272' from dual
	union select '280611' from dual
	union select '282479' from dual
	union select '283855' from dual
	union select '284458' from dual
	union select '284534' from dual
	union select '308351' from dual
	union select '308769' from dual
	union select '310710' from dual
	union select '310713' from dual
	union select '310723' from dual
	union select '310732' from dual
	union select '310733' from dual
	union select '310734' from dual
	union select '310739' from dual
	union select '310741' from dual
	union select '313410' from dual
	union select '313732' from dual
	union select '313733' from dual
	union select '313734' from dual
	union select '313735' from dual
	union select '313737' from dual
	union select '313738' from dual
	union select '313739' from dual
	union select '314013' from dual
	union select '314279' from dual
	union select '314280' from dual
	union select '321208' from dual
	union select '349308' from dual
	union select '351111' from dual
	union select '352081' from dual
	union select '352102' from dual
	union select '370743' from dual
	union select '371679' from dual
	union select '371810' from dual
	union select '372012' from dual
	union select '374319' from dual
	union select '374320' from dual
	union select '374638' from dual
	union select '376834' from dual
	union select '381158' from dual
	union select '389189' from dual
	union select '402248' from dual
	union select '402249' from dual
	union select '404141' from dual
	union select '404142' from dual
	union select '404143' from dual
	union select '404144' from dual
	union select '404146' from dual
	union select '404147' from dual
	union select '404148' from dual
	union select '404259' from dual
	union select '404260' from dual
	union select '415379' from dual
	union select '5224' from dual
	union select '540217' from dual
	union select '542824' from dual
	union select '545076' from dual
	union select '562130' from dual
	union select '562550' from dual
	union select '581236' from dual
	union select '60819' from dual
	union select '616862' from dual
	union select '616912' from dual
	union select '645887' from dual
	union select '67031' from dual
	union select '67108' from dual
	union select '67109' from dual
	union select '69646' from dual
	union select '727382' from dual
	union select '727383' from dual
	union select '727384' from dual
	union select '727559' from dual
	union select '727560' from dual
	union select '727562' from dual
	union select '727563' from dual
	union select '727564' from dual
	union select '727565' from dual
	union select '727566' from dual
	union select '727567' from dual
	union select '727568' from dual
	union select '727718' from dual
	union select '727719' from dual
	union select '727722' from dual
	union select '727723' from dual
	union select '727724' from dual
	union select '727725' from dual
	union select '727726' from dual
	union select '727727' from dual
	union select '727728' from dual
	union select '727729' from dual
	union select '727730' from dual
	union select '727778' from dual
	union select '727831' from dual
	union select '727832' from dual
	union select '727834' from dual
	union select '727838' from dual
	union select '727851' from dual
	union select '727859' from dual
	union select '727860' from dual
	union select '727861' from dual
	union select '727878' from dual
	union select '727880' from dual
	union select '727881' from dual
	union select '727882' from dual
	union select '727883' from dual
	union select '727884' from dual
	union select '727888' from dual
	union select '727892' from dual
	union select '727920' from dual
	union select '727922' from dual
	union select '727926' from dual
	union select '729968' from dual
	union select '729969' from dual
	union select '729970' from dual
	union select '729971' from dual
	union select '729972' from dual
	union select '729973' from dual
	union select '729974' from dual
	union select '729976' from dual
	union select '730002' from dual
	union select '746573' from dual
	union select '746574' from dual
	union select '753111' from dual
	union select '753112' from dual
	union select '753113' from dual
	union select '759595' from dual
	union select '759596' from dual
	union select '759597' from dual
	union select '759598' from dual
	union select '759599' from dual
	union select '75960' from dual
	union select '759600' from dual
	union select '759601' from dual
	union select '792060' from dual
	union select '795798' from dual
	union select '827000' from dual
	union select '827001' from dual
	union select '827003' from dual
	union select '827069' from dual
	union select '827099' from dual
	union select '829884' from dual
	union select '829885' from dual
	union select '829886' from dual
	union select '829888' from dual
	union select '830698' from dual
	union select '848335' from dual
	union select '848339' from dual
	union select '849297' from dual
	union select '849298' from dual
	union select '849299' from dual
	union select '849300' from dual
	union select '849301' from dual
	union select '849312' from dual
	union select '849313' from dual
	union select '849317' from dual
	union select '849333' from dual
	union select '849337' from dual
	union select '849338' from dual
	union select '849339' from dual
	union select '849340' from dual
	union select '849341' from dual
	union select '849342' from dual
	union select '849344' from dual
	union select '849699' from dual
	union select '849702' from dual
	union select '849710' from dual
	union select '849712' from dual
	union select '849715' from dual
	union select '849718' from dual
	union select '849722' from dual
	union select '849726' from dual
	union select '849764' from dual
	union select '849770' from dual
	union select '849776' from dual
	union select '849814' from dual
	union select '854228' from dual
	union select '854232' from dual
	union select '854235' from dual
	union select '854236' from dual
	union select '854238' from dual
	union select '854239' from dual
	union select '854241' from dual
	union select '854242' from dual
	union select '854245' from dual
	union select '854247' from dual
	union select '854248' from dual
	union select '854249' from dual
	union select '854252' from dual
	union select '854253' from dual
	union select '854255' from dual
	union select '854256' from dual
	union select '855288' from dual
	union select '855290' from dual
	union select '855292' from dual
	union select '855296' from dual
	union select '855298' from dual
	union select '855300' from dual
	union select '855302' from dual
	union select '855304' from dual
	union select '855306' from dual
	union select '855308' from dual
	union select '855312' from dual
	union select '855314' from dual
	union select '855316' from dual
	union select '855318' from dual
	union select '855320' from dual
	union select '855322' from dual
	union select '855324' from dual
	union select '855326' from dual
	union select '855328' from dual
	union select '855332' from dual
	union select '855334' from dual
	union select '855336' from dual
	union select '855338' from dual
	union select '855340' from dual
	union select '855342' from dual
	union select '855344' from dual
	union select '855346' from dual
	union select '855348' from dual
	union select '855350' from dual
	union select '857253' from dual
	union select '857255' from dual
	union select '857257' from dual
	union select '857259' from dual
	union select '857261' from dual
	union select '857645' from dual
	union select '861356' from dual
	union select '861358' from dual
	union select '861360' from dual
	union select '861362' from dual
	union select '861363' from dual
	union select '861364' from dual
	union select '861365' from dual
	union select '861366' from dual
	union select '978713' from dual
	union select '978715' from dual
	union select '978717' from dual
	union select '978718' from dual
	union select '978719' from dual
	union select '978720' from dual
	union select '978721' from dual
	union select '978722' from dual
	union select '978723' from dual
	union select '978725' from dual
	union select '978727' from dual
	union select '978733' from dual
	union select '978735' from dual
	union select '978736' from dual
	union select '978737' from dual
	union select '978738' from dual
	union select '978740' from dual
	union select '978741' from dual
	union select '978744' from dual
	union select '978745' from dual
	union select '978746' from dual
	union select '978747' from dual
	union select '978755' from dual
	union select '978757' from dual
	union select '978759' from dual
	union select '978761' from dual
	union select '978777' from dual
	union select '978778' from dual) t
union select 'COVIDVIRAL' m, c from
	(select '108766' c from dual
	union select '1236627' from dual
	union select '1236628' from dual
	union select '1236632' from dual
	union select '1298334' from dual
	union select '1359269' from dual
	union select '1359271' from dual
	union select '1486197' from dual
	union select '1486198' from dual
	union select '1486200' from dual
	union select '1486202' from dual
	union select '1486203' from dual
	union select '1487498' from dual
	union select '1487500' from dual
	union select '1863148' from dual
	union select '1992160' from dual
	union select '207406' from dual
	union select '248109' from dual
	union select '248110' from dual
	union select '248112' from dual
	union select '284477' from dual
	union select '284640' from dual
	union select '311368' from dual
	union select '311369' from dual
	union select '312817' from dual
	union select '312818' from dual
	union select '352007' from dual
	union select '352337' from dual
	union select '373772' from dual
	union select '373773' from dual
	union select '373774' from dual
	union select '374642' from dual
	union select '374643' from dual
	union select '376293' from dual
	union select '378671' from dual
	union select '460132' from dual
	union select '539485' from dual
	union select '544400' from dual
	union select '597718' from dual
	union select '597722' from dual
	union select '597729' from dual
	union select '597730' from dual
	union select '602770' from dual
	union select '616129' from dual
	union select '616131' from dual
	union select '616133' from dual
	union select '643073' from dual
	union select '643074' from dual
	union select '670026' from dual
	union select '701411' from dual
	union select '701413' from dual
	union select '746645' from dual
	union select '746647' from dual
	union select '754738' from dual
	union select '757597' from dual
	union select '757598' from dual
	union select '757599' from dual
	union select '757600' from dual
	union select '790286' from dual
	union select '794610' from dual
	union select '795742' from dual
	union select '795743' from dual
	union select '824338' from dual
	union select '824876' from dual
	union select '831868' from dual
	union select '831870' from dual
	union select '847330' from dual
	union select '847741' from dual
	union select '847745' from dual
	union select '847749' from dual
	union select '850455' from dual
	union select '850457' from dual
	union select '896790' from dual
	union select '902312' from dual
	union select '902313' from dual
	union select '9344' from dual) t
union select 'DIURETIC' m, c from
	(select '392534' c from dual
	union select '4109' from dual
	union select '392464' from dual
	union select '33770' from dual
	union select '104220' from dual
	union select '104222' from dual
	union select '1112201' from dual
	union select '132604' from dual
	union select '1488537' from dual
	union select '1546054' from dual
	union select '1546056' from dual
	union select '1719285' from dual
	union select '1719286' from dual
	union select '1719290' from dual
	union select '1719291' from dual
	union select '1727568' from dual
	union select '1727569' from dual
	union select '1727572' from dual
	union select '1729520' from dual
	union select '1729521' from dual
	union select '1729523' from dual
	union select '1729527' from dual
	union select '1729528' from dual
	union select '1808' from dual
	union select '197417' from dual
	union select '197418' from dual
	union select '197419' from dual
	union select '197730' from dual
	union select '197731' from dual
	union select '197732' from dual
	union select '198369' from dual
	union select '198370' from dual
	union select '198371' from dual
	union select '198372' from dual
	union select '199610' from dual
	union select '200801' from dual
	union select '200809' from dual
	union select '204154' from dual
	union select '205488' from dual
	union select '205489' from dual
	union select '205490' from dual
	union select '205732' from dual
	union select '208076' from dual
	union select '208078' from dual
	union select '208080' from dual
	union select '208081' from dual
	union select '208082' from dual
	union select '248657' from dual
	union select '250044' from dual
	union select '250660' from dual
	union select '251308' from dual
	union select '252484' from dual
	union select '282452' from dual
	union select '282486' from dual
	union select '310429' from dual
	union select '313988' from dual
	union select '371157' from dual
	union select '371158' from dual
	union select '372280' from dual
	union select '372281' from dual
	union select '374168' from dual
	union select '374368' from dual
	union select '38413' from dual
	union select '404018' from dual
	union select '4603' from dual
	union select '545041' from dual
	union select '561969' from dual
	union select '630032' from dual
	union select '630035' from dual
	union select '645036' from dual
	union select '727573' from dual
	union select '727574' from dual
	union select '727575' from dual
	union select '727845' from dual
	union select '876422' from dual
	union select '95600' from dual) t
union select 'HCQ' m, c from
      	(select '1116758' c from dual
	union select '1116760' from dual
	union select '1117346' from dual
	union select '1117351' from dual
	union select '1117353' from dual
	union select '1117531' from dual
	union select '197474' from dual
	union select '197796' from dual
	union select '202317' from dual
	union select '213378' from dual
	union select '226388' from dual
	union select '2393' from dual
	union select '249663' from dual
	union select '250175' from dual
	union select '261104' from dual
	union select '370656' from dual
	union select '371407' from dual
	union select '5521' from dual
	union select '755624' from dual
	union select '755625' from dual
	union select '756408' from dual
	union select '979092' from dual
	union select '979094' from dual) t
union select 'ILI' m, c from
      	(select '1441526' c from dual
	union select '1441527' from dual
	union select '1441530' from dual
	union select '1535218' from dual
	union select '1535242' from dual
	union select '1535247' from dual
	union select '1657973' from dual
	union select '1657974' from dual
	union select '1657976' from dual
	union select '1657979' from dual
	union select '1657980' from dual
	union select '1657981' from dual
	union select '1657982' from dual
	union select '1658131' from dual
	union select '1658132' from dual
	union select '1658135' from dual
	union select '1658139' from dual
	union select '1658141' from dual
	union select '1923319' from dual
	union select '1923332' from dual
	union select '1923333' from dual
	union select '1923338' from dual
	union select '1923345' from dual
	union select '1923347' from dual
	union select '2003754' from dual
	union select '2003755' from dual
	union select '2003757' from dual
	union select '2003766' from dual
	union select '2003767' from dual
	union select '351141' from dual
	union select '352056' from dual
	union select '612865' from dual
	union select '72435' from dual
	union select '727708' from dual
	union select '727711' from dual
	union select '727714' from dual
	union select '727715' from dual
	union select '895760' from dual
	union select '895764' from dual) t
union select 'INTERFERON' m, c from
	(select '120608' c from dual
	union select '1650893' from dual
	union select '1650894' from dual
	union select '1650896' from dual
	union select '1650922' from dual
	union select '1650940' from dual
	union select '1651307' from dual
	union select '1721323' from dual
	union select '198360' from dual
	union select '207059' from dual
	union select '351270' from dual
	union select '352297' from dual
	union select '378926' from dual
	union select '403986' from dual
	union select '72257' from dual
	union select '731325' from dual
	union select '731326' from dual
	union select '731328' from dual
	union select '731330' from dual
	union select '860244' from dual) t
union select 'SIANES' m, c from
	(select '106517' c from dual
	union select '1087926' from dual
	union select '1188478' from dual
	union select '1234995' from dual
	union select '1242617' from dual
	union select '1249681' from dual
	union select '1301259' from dual
	union select '1313988' from dual
	union select '1373737' from dual
	union select '1486837' from dual
	union select '1535224' from dual
	union select '1535226' from dual
	union select '1535228' from dual
	union select '1535230' from dual
	union select '1551393' from dual
	union select '1551395' from dual
	union select '1605773' from dual
	union select '1666776' from dual
	union select '1666777' from dual
	union select '1666797' from dual
	union select '1666798' from dual
	union select '1666800' from dual
	union select '1666814' from dual
	union select '1666821' from dual
	union select '1666823' from dual
	union select '1718899' from dual
	union select '1718900' from dual
	union select '1718902' from dual
	union select '1718906' from dual
	union select '1718907' from dual
	union select '1718909' from dual
	union select '1718910' from dual
	union select '1730193' from dual
	union select '1730194' from dual
	union select '1730196' from dual
	union select '1732667' from dual
	union select '1732668' from dual
	union select '1732674' from dual
	union select '1788947' from dual
	union select '1808216' from dual
	union select '1808217' from dual
	union select '1808219' from dual
	union select '1808222' from dual
	union select '1808223' from dual
	union select '1808224' from dual
	union select '1808225' from dual
	union select '1808234' from dual
	union select '1808235' from dual
	union select '1862110' from dual
	union select '198383' from dual
	union select '199211' from dual
	union select '199212' from dual
	union select '199775' from dual
	union select '2050125' from dual
	union select '2057964' from dual
	union select '206967' from dual
	union select '206970' from dual
	union select '206972' from dual
	union select '207793' from dual
	union select '207901' from dual
	union select '210676' from dual
	union select '210677' from dual
	union select '238082' from dual
	union select '238083' from dual
	union select '238084' from dual
	union select '240606' from dual
	union select '259859' from dual
	union select '284397' from dual
	union select '309710' from dual
	union select '311700' from dual
	union select '311701' from dual
	union select '311702' from dual
	union select '312674' from dual
	union select '319864' from dual
	union select '372528' from dual
	union select '372922' from dual
	union select '375623' from dual
	union select '376856' from dual
	union select '377135' from dual
	union select '377219' from dual
	union select '377483' from dual
	union select '379133' from dual
	union select '404091' from dual
	union select '404092' from dual
	union select '404136' from dual
	union select '422410' from dual
	union select '446503' from dual
	union select '48937' from dual
	union select '584528' from dual
	union select '584530' from dual
	union select '6130' from dual
	union select '631205' from dual
	union select '68139' from dual
	union select '6960' from dual
	union select '71535' from dual
	union select '828589' from dual
	union select '828591' from dual
	union select '830752' from dual
	union select '859437' from dual
	union select '8782' from dual
	union select '884675' from dual
	union select '897073' from dual
	union select '897077' from dual
	union select '998210' from dual
	union select '998211' from dual) t
union select 'SICARDIAC' m, c from
	(select '7442' c from dual
	union select '1009216' from dual
	union select '1045470' from dual
	union select '1049182' from dual
	union select '1049184' from dual
	union select '1052767' from dual
	union select '106686' from dual
	union select '106779' from dual
	union select '106780' from dual
	union select '1087043' from dual
	union select '1087047' from dual
	union select '1090087' from dual
	union select '1114874' from dual
	union select '1114880' from dual
	union select '1114888' from dual
	union select '11149' from dual
	union select '1117374' from dual
	union select '1232651' from dual
	union select '1232653' from dual
	union select '1234563' from dual
	union select '1234569' from dual
	union select '1234571' from dual
	union select '1234576' from dual
	union select '1234578' from dual
	union select '1234579' from dual
	union select '1234581' from dual
	union select '1234584' from dual
	union select '1234585' from dual
	union select '1234586' from dual
	union select '1251018' from dual
	union select '1251022' from dual
	union select '1292716' from dual
	union select '1292731' from dual
	union select '1292740' from dual
	union select '1292751' from dual
	union select '1292887' from dual
	union select '1299137' from dual
	union select '1299141' from dual
	union select '1299145' from dual
	union select '1299879' from dual
	union select '1300092' from dual
	union select '1302755' from dual
	union select '1305268' from dual
	union select '1305269' from dual
	union select '1307224' from dual
	union select '1358843' from dual
	union select '1363777' from dual
	union select '1363785' from dual
	union select '1363786' from dual
	union select '1363787' from dual
	union select '1366958' from dual
	union select '141848' from dual
	union select '1490057' from dual
	union select '1542385' from dual
	union select '1546216' from dual
	union select '1546217' from dual
	union select '1547926' from dual
	union select '1548673' from dual
	union select '1549386' from dual
	union select '1549388' from dual
	union select '1593738' from dual
	union select '1658178' from dual
	union select '1660013' from dual
	union select '1660014' from dual
	union select '1660016' from dual
	union select '1661387' from dual
	union select '1666371' from dual
	union select '1666372' from dual
	union select '1666374' from dual
	union select '1721536' from dual
	union select '1743862' from dual
	union select '1743869' from dual
	union select '1743871' from dual
	union select '1743877' from dual
	union select '1743879' from dual
	union select '1743938' from dual
	union select '1743941' from dual
	union select '1743950' from dual
	union select '1743953' from dual
	union select '1745276' from dual
	union select '1789858' from dual
	union select '1791839' from dual
	union select '1791840' from dual
	union select '1791842' from dual
	union select '1791854' from dual
	union select '1791859' from dual
	union select '1791861' from dual
	union select '1812167' from dual
	union select '1812168' from dual
	union select '1812170' from dual
	union select '1870205' from dual
	union select '1870207' from dual
	union select '1870225' from dual
	union select '1870230' from dual
	union select '1870232' from dual
	union select '1939322' from dual
	union select '198620' from dual
	union select '198621' from dual
	union select '198786' from dual
	union select '198787' from dual
	union select '198788' from dual
	union select '1989112' from dual
	union select '1989117' from dual
	union select '1991328' from dual
	union select '1991329' from dual
	union select '1999003' from dual
	union select '1999006' from dual
	union select '1999007' from dual
	union select '1999012' from dual
	union select '204395' from dual
	union select '204843' from dual
	union select '209217' from dual
	union select '2103181' from dual
	union select '2103182' from dual
	union select '2103184' from dual
	union select '211199' from dual
	union select '211200' from dual
	union select '211704' from dual
	union select '211709' from dual
	union select '211712' from dual
	union select '211714' from dual
	union select '211715' from dual
	union select '212343' from dual
	union select '212770' from dual
	union select '212771' from dual
	union select '212772' from dual
	union select '212773' from dual
	union select '238217' from dual
	union select '238218' from dual
	union select '238219' from dual
	union select '238230' from dual
	union select '238996' from dual
	union select '238997' from dual
	union select '238999' from dual
	union select '239000' from dual
	union select '239001' from dual
	union select '241033' from dual
	union select '242969' from dual
	union select '244284' from dual
	union select '245317' from dual
	union select '247596' from dual
	union select '247940' from dual
	union select '260687' from dual
	union select '309985' from dual
	union select '309986' from dual
	union select '309987' from dual
	union select '310011' from dual
	union select '310012' from dual
	union select '310013' from dual
	union select '310116' from dual
	union select '310117' from dual
	union select '310127' from dual
	union select '310132' from dual
	union select '311705' from dual
	union select '312395' from dual
	union select '312398' from dual
	union select '313578' from dual
	union select '313967' from dual
	union select '314175' from dual
	union select '347930' from dual
	union select '351701' from dual
	union select '351702' from dual
	union select '351982' from dual
	union select '359907' from dual
	union select '3616' from dual
	union select '3628' from dual
	union select '372029' from dual
	union select '372030' from dual
	union select '372031' from dual
	union select '373368' from dual
	union select '373369' from dual
	union select '373370' from dual
	union select '373372' from dual
	union select '373375' from dual
	union select '374283' from dual
	union select '374570' from dual
	union select '376521' from dual
	union select '377281' from dual
	union select '379042' from dual
	union select '387789' from dual
	union select '392099' from dual
	union select '393309' from dual
	union select '3992' from dual
	union select '404093' from dual
	union select '477358' from dual
	union select '477359' from dual
	union select '52769' from dual
	union select '542391' from dual
	union select '542655' from dual
	union select '542674' from dual
	union select '562501' from dual
	union select '562502' from dual
	union select '562592' from dual
	union select '584580' from dual
	union select '584582' from dual
	union select '584584' from dual
	union select '584588' from dual
	union select '602511' from dual
	union select '603259' from dual
	union select '603276' from dual
	union select '603915' from dual
	union select '617785' from dual
	union select '669267' from dual
	union select '672683' from dual
	union select '672685' from dual
	union select '672891' from dual
	union select '692479' from dual
	union select '700414' from dual
	union select '704955' from dual
	union select '705163' from dual
	union select '705164' from dual
	union select '705170' from dual
	union select '727310' from dual
	union select '727316' from dual
	union select '727345' from dual
	union select '727347' from dual
	union select '727373' from dual
	union select '727386' from dual
	union select '727410' from dual
	union select '727842' from dual
	union select '727843' from dual
	union select '727844' from dual
	union select '746206' from dual
	union select '746207' from dual
	union select '7512' from dual
	union select '8163' from dual
	union select '827706' from dual
	union select '864089' from dual
	union select '880658' from dual
	union select '8814' from dual
	union select '883806' from dual
	union select '891437' from dual
	union select '891438' from dual) t
	) t;
commit;
-- Remdesivir defined separately since many sites will have custom codes (optional)
insert into fource_med_map
	select 'REMDESIVIR', 'RxNorm', 'RxNorm:2284718' from dual
	union select 'REMDESIVIR', 'RxNorm', 'RxNorm:2284960' from dual
	union select 'REMDESIVIR', 'Custom', 'ACT|LOCAL:REMDESIVIR' from dual;
commit;
-- Use the concept_dimension to get an expanded list of medication codes (optional)
-- This will find paths corresponding to concepts already in the fource_med_map table,
-- and then find all the concepts corresponding to child paths.
-- WARNING: This query might take several minutes to run.
-- ****THIS IS UNTESTED ******
/*
select concept_path, concept_cd
	into #med_paths
	from @crcSchema.concept_dimension
	where concept_path like '\ACT\Medications\%'
		and concept_cd in (select concept_cd from @crcSchema.observation_fact --with (nolock)) 
; alter table #med_paths add primary key (concept_path)
; insert into fource_med_map
	select distinct m.med_class, 'Expand', d.concept_cd
	from fource_med_map m
		inner join @crcSchema.concept_dimension c
			on m.local_med_code = c.concept_cd
		inner join #med_paths d
			on d.concept_path like c.concept_path || '%'
	where not exists (
		select *
		from fource_med_map t
		where t.med_class = m.med_class and t.local_med_code = d.concept_cd
	)
*/

--------------------------------------------------------------------------------
-- Procedure mappings
-- * Do not change the proc_group or add additional procedures.
--------------------------------------------------------------------------------
create table fource_proc_map (
	proc_group varchar(50) not null,
	code_type varchar(10) not null,
	local_proc_code varchar(50) not null
);
alter table fource_proc_map add primary key (proc_group, code_type, local_proc_code);

-- CPT4 (United States)
insert into fource_proc_map
	select p, 'CPT4', 'CPT4:' || c  -- Change "CPT4:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c from dual where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select '44970' c from dual union select '47562' from dual 
            union select '47563' from dual union select '44950' from dual union select '49320' from dual 
            union select '44180' from dual union select '49585' from dual union select '44120' from dual) t
		union all select 'EmergencyOrthopedics', c from (select '27245' c from dual union select '27236' from dual 
            union select '27759' from dual union select '24538' from dual union select '11044' from dual 
            union select '27506' from dual union select '22614' from dual union select '27814' from dual 
            union select '63030' from dual) t
		union all select 'EmergencyVascularSurgery', c from (select '36247' c from dual) t
		union all select 'EmergencyOBGYN', c from (select '59151' c from dual) t 
		union all select 'RenalReplacement', c from (select '90935' c from dual union select '90937' from dual 
            union select '90945' from dual) t
		union all select 'SupplementalOxygenSevere', c from (select '94002' c from dual union select '94003' from dual 
            union select '94660' from dual union select '31500' from dual) t
		union all select 'ECMO', c from (select '33946' c from dual union select '33947' from dual 
            union select '33951' from dual union select '33952' from dual) t
		union all select 'CPR', c from (select '92950' c from dual) t
		union all select 'ArterialCatheter', c from (select '36620' c from dual) t
		union all select 'CTChest', c from (select '71250' c from dual union select '71260' from dual 
            union select '71270' from dual) t
		union all select 'Bronchoscopy', c from (select '31645' c from dual) t
		union all select 'CovidVaccine', c from (select '0001A' c from dual union select '0002A' from dual 
            union select '0011A' from dual union select '0012A' from dual union select '0021A' from dual 
            union select '0022A' from dual union select '0031A' from dual union select '91300' from dual 
            union select '91301' from dual union select '91302' from dual union select '91303' from dual) t
	) t;
commit;
-- CCAM (France)
insert into fource_proc_map
	select p, 'CCAM', 'CCAM:' || c  -- Change "CCAM:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c from dual where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select 'HHFA016' c from dual union select 'HMFC004' from dual 
            union select 'HHFA011' from dual union select 'ZCQC002' from dual union select 'HGPC015' from dual 
            union select 'LMMA006' from dual union select 'LMMA009' from dual union select 'HGFA007' from dual 
            union select 'HGFC021' from dual) t
		union all select 'EmergencyOrthopedics', c from (select 'NBCA006' c from dual union select 'NBCA005' from dual 
            union select 'NCCB006' from dual union select 'MBCB001' from dual union select 'NBCA007' from dual 
            union select 'LHDA001' from dual union select 'LHDA002' from dual union select 'NCCA017' from dual 
            union select 'LFFA001' from dual union select 'LDFA003' from dual) t
		union all select 'EmergencyOBGYN', c from (select 'JJFC001' c from dual) t
		union all select 'RenalReplacement', c from (select 'JVJF004' c from dual union select 'JVJF005' from dual 
            union select 'JVJF004' from dual union select 'JVJB001' from dual union select 'JVJB002' from dual 
            union select 'JVJF003' from dual union select 'JVJF008' from dual) t
		union all select 'SupplementalOxygenSevere', c from (select 'GLMF001' c from dual union select 'GLLD003' from dual 
            union select 'GLLD012' from dual union select 'GLLD019' from dual union select 'GLMP001' from dual 
            union select 'GLLD008' from dual union select 'GLLD015' from dual union select 'GLLD004' from dual 
            union select 'GELD004' from dual) t
		union all select 'SupplementalOxygenOther', c from (select 'GLLD017' c from dual) t
		union all select 'ECMO', c from (select 'EQLA002' c from dual union select 'EQQP004' from dual union select 'GLJF010' from dual) t
		union all select 'CPR', c from (select 'DKMD001' c from dual union select 'DKMD002' from dual) t
		union all select 'ArterialCatheter', c from (select 'ENLF001' c from dual) t
		union all select 'CTChest', c from (select 'ZBQK001' c from dual union select 'ZBQH001' from dual) t
		union all select 'Bronchoscopy', c from (select 'GEJE001' c from dual union select 'GEJE003' from dual) t
	) t;
commit;

-- OPCS4 (United Kingdom)
insert into fource_proc_map
	select p, 'OPCS4', 'OPCS4:' || c  -- Change "OPCS4:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c from dual where 1=0
        union all select 'EmergencyGeneralSurgery', c from (select 'H01' c from dual union select 'Y75.2' from dual 
            union select 'J18' from dual union select 'Y75.2' from dual union select 'J18.2' from dual 
            union select 'Y75.2' from dual union select 'H01' from dual union select 'T43' from dual 
            union select 'T43.8' from dual union select 'T41.3' from dual union select 'T24' from dual 
            union select 'G58.4' from dual union select 'G69.3' from dual) t
		union all select 'EmergencyOrthopedics', c from (select 'W24.1' c from dual union select 'W19.1' from dual 
            union select 'W33.6' from dual union select 'W19.2' from dual union select 'V38' from dual 
            union select 'V55.1' from dual union select 'W20.5' from dual union select 'V25.2' from dual 
            union select 'V67.2' from dual union select 'V55.1' from dual) t
		union all select 'RenalReplacement', c from (select 'X40.3' c from dual union select 'X40.3' from dual 
            union select 'X40.2' from dual union select 'X40.4' from dual union select 'X40.5' from dual 
            union select 'X40.6' from dual union select 'X40.7' from dual union select 'X40.8' from dual union select 'X40.9' from dual) t
		union all select 'SupplementalOxygenSevere', c from (select 'E85.2' c from dual union select 'E85.4' from dual 
            union select 'E85.6' from dual union select 'X56.2' from dual) t
		union all select 'SupplementalOxygenOther', c from (select 'X52' c from dual) t
		union all select 'ECMO', c from (select 'X58.1' c from dual union select 'X58.1' from dual 
            union select 'X58.1' from dual union select 'X58.1' from dual) t
		union all select 'CPR', c from (select 'X50.3' c from dual) t
		union all select 'CTChest', c from (select 'U07.1' c from dual union select 'Y97.2' from dual 
            union select 'U07.1' from dual union select 'Y97.3' from dual union select 'U07.1' from dual union select 'Y97.1' from dual) t
		union all select 'Bronchoscopy', c from (select 'E48.4' c from dual union select 'E50.4' from dual) t
	) t;

-- OPS (Germany)
insert into fource_proc_map
	select p, 'OPS', 'OPS:' || c  -- Change "OPS:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c  from dual where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select '5-470.1' c from dual union select '5-511.1' from dual 
            union select '5-511.12' from dual union select '5-470' from dual union select '1-694' from dual 
            union select '5-534' from dual union select '5-459.0' from dual) t
		union all select 'EmergencyOrthopedics', c from (select '5-790.2f' c from dual union select '5-793.1e' from dual 
            union select '5-790.2m' from dual union select '5-791.6m' from dual union select '5-790.13' from dual 
            union select '5-780.6' from dual union select '5-791.6g' from dual union select '5-836.30' from dual 
            union select '5-032.30' from dual) t
		union all select 'RenalReplacement', c from (select '8-854' c from dual union select '8-854' from dual 
            union select '8-857' from dual union select '8-853' from dual union select '8-855' from dual 
            union select '8-856' from dual) t
		union all select 'SupplementalOxygenSevere', c from (select '8-716.00' c from dual 
            union select '8-711.0' from dual union select '8-712.0' from dual union select '8-701' from dual) t
		union all select 'SupplementalOxygenOther', c from (select '8-72' c from dual) t
		union all select 'ECMO', c from (select '8-852.0' c from dual union select '8-852.30' from dual union select '8-852.31' from dual) t
		union all select 'CPR', c from (select '8-771' c from dual) t
		union all select 'CTChest', c from (select '3-202' c from dual union select '3-221' from dual) t
	) t;

-- TOSP (Singapore)
insert into fource_proc_map
	select p, 'TOSP', 'TOSP:' || c  -- Change "TOSP:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c from dual where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select 'SF849A' c from dual union select 'SF801G' from dual 
            union select 'SF704G' from dual union select 'SF849A' from dual union select 'SF808A' from dual 
            union select 'SF800A' from dual union select 'SF801A' from dual union select 'SF814A' from dual 
            union select 'SF707I' from dual) t
		union all select 'EmergencyOrthopedics', c from (select 'SB811F' c from dual union select 'SB703F' from dual 
            union select 'SB705T' from dual union select 'SB810F' from dual union select 'SB700A' from dual 
            union select 'SB812S' from dual) t
		union all select 'EmergencyOBGYN', c from (select 'SI805F' c from dual) t
		union all select 'SupplementalOxygenSevere', c from (select 'SC719T' c from dual union select 'SC720T' from dual) t
		union all select 'ECMO', c from (select 'SD721H' c from dual union select 'SD721H' from dual 
            union select 'SD721H' from dual union select 'SD721H' from dual) t
		union all select 'ArterialCatheter', c from (select 'SD718A' c from dual) t
		union all select 'Bronchoscopy', c from (select 'SC703B' c from dual union select 'SC704B' from dual) t
	) t;

-- ICD10AM (Singapore, Australia)
insert into fource_proc_map
	select p, 'ICD10AM', 'ICD10AM:' || c  -- Change "ICD10AM:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c from dual where 1=0
		union all select 'RenalReplacement', c from (select '13100-00' c from dual union select '13100-00' from dual) t
		union all select 'SupplementalOxygenSevere', c from (select '92039-00' c from dual union select '13882-00' from dual 
            union select '13882-01' from dual union select '92038-00' from dual) t
		union all select 'SupplementalOxygenOther', c from (select '92044-00' c from dual) t
		union all select 'CPR', c from (select '92052-00' c from dual) t
	) t;

-- CBHPM (Brazil-TUSS)
insert into fource_proc_map
	select p, 'CBHPM', 'CBHPM:' || c  -- Change "CBHPM:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c from dual where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select '31003079' c from dual union select '31005497' from dual 
            union select '31005470' from dual union select '31003079' from dual union select '31009166' from dual) t
		union all select 'EmergencyOrthopedics', c from (select '30725119' c from dual union select '30725160' from dual 
            union select '30727138' from dual union select '40803104' from dual union select '30715016' from dual 
            union select '30715199' from dual) t
		union all select 'EmergencyOBGYN', c from (select '31309186' c from dual) t
		union all select 'RenalReplacement', c from (select '30909023' c from dual union select '30909031' from dual 
            union select '31008011' from dual) t
		union all select 'SupplementalOxygenSevere', c from (select '20203012' c from dual union select '20203012' from dual 
            union select '40202445' from dual) t
		union all select 'Bronchoscopy', c from (select '40201058' c from dual) t
	) t;

-- ICD9Proc
insert into fource_proc_map
	select p, 'ICD9', 'ICD9PROC:' || c  -- Change "ICD9:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c from dual where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select '47.01' c from dual union select '51.23' from dual 
            union select '47.0' from dual union select '54.51' from dual union select '53.4' from dual) t
		union all select 'EmergencyOrthopedics', c from (select '79.11' c from dual union select '79.6' from dual 
            union select '79.35' from dual union select '81.03' from dual union select '81.05' from dual 
            union select '81.07' from dual union select '79.36' from dual) t
		union all select 'EmergencyOBGYN', c from (select '66.62' c from dual) t
		union all select 'RenalReplacement', c from (select '39.95' c from dual union select '39.95' from dual) t
		union all select 'SupplementalOxygenSevere', c from (select '93.90' c from dual union select '96.70' from dual 
            union select '96.71' from dual union select '96.72' from dual union select '96.04' from dual) t
		union all select 'SupplementalOxygenOther', c from (select '93.96' c from dual) t
		union all select 'ECMO', c from (select '39.65' c from dual union select '39.65' from dual 
            union select '39.65' from dual union select '39.65' from dual) t
		union all select 'CPR', c from (select '99.60' c from dual) t
		union all select 'ArterialCatheter', c from (select '38.91' c from dual) t
		union all select 'CTChest', c from (select '87.41' c from dual union select '87.41' from dual 
            union select '87.41' from dual) t
		union all select 'Bronchoscopy', c from (select '33.22' c from dual union select '33.23' from dual) t
	) t;
commit;
-- ICD10-PCS
insert into fource_proc_map
	select p, 'ICD10', 'ICD10PCS:' || c  -- Change "ICD10:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c  from dual where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select '0DBJ4ZZ' c from dual union select '0DTJ4ZZ' from dual 
            union select '0FB44ZZ' from dual union select '0FB44ZX' from dual union select '0DBJ0ZZ' from dual 
            union select '0DTJ0ZZ' from dual union select '0DJU4ZZ' from dual union select '0DN84ZZ' from dual 
            union select '0DNE4ZZ' from dual) t
		union all select 'EmergencyOrthopedics', c from (select '0QQ60ZZ' c from dual union select '0QQ70ZZ' from dual 
            union select '0QH806Z' from dual union select '0QH906Z' from dual) t
		union all select 'SupplementalOxygenSevere', c from (select '5A19054' c from dual union select '5A0935Z' from dual 
            union select '5A0945Z' from dual union select '5A0955Z' from dual union select '5A09357' from dual 
            union select '0BH17EZ' from dual) t
		union all select 'ECMO', c from (select '5A1522H' c from dual union select '5A1522G' from dual) t
		union all select 'CTChest', c from (select 'BW24' c from dual union select 'BW24Y0Z' from dual union select 'BW24YZZ' from dual) t
	) t;
commit;
-- SNOMED
insert into fource_proc_map
	select p, 'SNOMED', 'SNOMED:' || c  -- Change "SNOMED:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c from dual where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select '174041007' c from dual union select '45595009' from dual 
            union select '20630000' from dual union select '80146002' from dual union select '450435004' from dual 
            union select '18433007' from dual union select '5789003' from dual union select '44946007' from dual 
            union select '359572002' from dual) t
		union all select 'EmergencyOrthopedics', c from (select '179097007' c from dual union select '179018001' from dual 
            union select '73156009' from dual union select '2480009' from dual union select '36939002' from dual 
            union select '55705006' from dual union select '439756000' from dual union select '302129007' from dual 
            union select '231045009' from dual union select '3968003' from dual union select '260648008' from dual 
            union select '178619000' from dual) t
		union all select 'EmergencyVascularSurgery', c from (select '392247006' c from dual) t
		union all select 'EmergencyOBGYN', c from (select '63596003' c from dual union select '61893009' from dual) t
		union all select 'RenalReplacement', c from (select '302497006' c from dual union select '302497006' from dual) t
		union all select 'SupplementalOxygenSevere', c from (select '428311008' c from dual union select '410210009' from dual 
            union select '409025002' from dual union select '47545007' from dual union select '16883004' from dual) t
		union all select 'SupplementalOxygenOther', c from (select '57485005' c from dual) t
		union all select 'ECMO', c from (select '786453001' c from dual union select '786451004' from dual) t
		union all select 'CPR', c from (select '150819003' c from dual) t
		union all select 'ArterialCatheter', c from (select '392248001' c from dual) t
		union all select 'CTChest', c from (select '395081000119108' c from dual union select '75385009' from dual 
            union select '169069000' from dual) t
		union all select 'Bronchoscopy', c from (select '10847001' c from dual union select '68187007' from dual) t
	) t;
commit;
-- Use the concept_dimension to get an expanded list of medication codes (optional)
-- This will find paths corresponding to concepts already in the fource_med_map table,
-- and then find all the concepts corresponding to child paths.
-- WARNING: This query might take several minutes to run.
-- ***** THIS IS UNTESTED *****
/* 
select concept_path, concept_cd
	into #med_paths
	from @crcSchema.concept_dimension
	where concept_path like '\ACT\Medications\%'
		and concept_cd in (select concept_cd from @crcSchema.observation_fact --with (nolock)) 
; alter table #med_paths add primary key (concept_path)
; insert into fource_med_map
	select distinct m.med_class, 'Expand', d.concept_cd
	from fource_med_map m
		inner join @crcSchema.concept_dimension c
			on m.local_med_code = c.concept_cd
		inner join #med_paths d
			on d.concept_path like c.concept_path || '%'
	where not exists (
		select *
		from fource_med_map t
		where t.med_class = m.med_class and t.local_med_code = d.concept_cd
	)
*/

--------------------------------------------------------------------------------
-- Multisystem Inflammatory Syndrome in Children (MIS-C) (optional)
-- * Write a custom query to populate this table with the patient_num's of
-- * children who develop MIS-C and their first MIS-C diagnosis date.
--------------------------------------------------------------------------------
drop table fource_misc;
create table fource_misc (
	patient_num int not null,
	misc_date date not null
);
alter table fource_misc add primary key (patient_num);
insert into fource_misc
	select -1, '01-JAN-1900' from dual where 1=0;
	--Replace with a list of patients and MIS-C diagnosis dates
	--union all select 1, '3/1/2020' from dual 
	--union all select 2, '4/1/2020' from dual;
commit;

--------------------------------------------------------------------------------
-- Cohorts
-- * In general, use the default values that select patients who were admitted
-- * with a positive COVID test result, broken out in three-month blocks.
-- * Modify this table only if you are working on a specific project that
-- * has defined custom patient cohorts to analyze.
--------------------------------------------------------------------------------
create table fource_cohort_config (
	cohort varchar(50) not null,
	include_in_phase1 int, -- 1 = include the cohort in the phase 1 output, otherwise 0
	include_in_phase2 int, -- 1 = include the cohort in the phase 2 output and saved files, otherwise 0
	source_data_updated_date date, -- the date your source data were last updated; set to NULL to use the value in the fource_config table
	earliest_adm_date date, -- the earliest possible admission date allowed in this cohort (NULL if no minimum date)
	latest_adm_date date -- the lastest possible admission date allowed this cohort (NULL if no maximum date)
); 

alter table fource_cohort_config add primary key (cohort);

insert into fource_cohort_config
	select 'PosAdm2020Q1', 1, 1, NULL, '01-JAN-2020', '31-MAR-2020' from dual
	union all select 'PosAdm2020Q2', 1, 1, NULL, '01-APR-2020', '30-JUN-2020' from dual
	union all select 'PosAdm2020Q3', 1, 1, NULL, '01-JUL-2020', '30-SEP-2020' from dual
	union all select 'PosAdm2020Q4', 1, 1, NULL, '01-OCT-2020', '31-DEC-2020' from dual
	union all select 'PosAdm2021Q1', 1, 1, NULL, '01-JAN-2021', '31-MAR-2021' from dual
	union all select 'PosAdm2021Q2', 1, 1, NULL, '01-APR-2021', '30-JUN-2021' from dual
	union all select 'PosAdm2021Q3', 1, 1, NULL, '01-JUL-2021', '30-SEP-2021' from dual
	union all select 'PosAdm2021Q4', 1, 1, NULL, '01-OCT-2021', '31-DEC-2021' from dual;
commit;
-- Assume the data were updated on the date this script is run if source_data_updated_date is null
update fource_cohort_config
	set source_data_updated_date = nvl((select source_data_updated_date from fource_config),sysdate)
	where source_data_updated_date is null;
commit;

--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--###
--### Get COVID test results, admission, ICU dates, and death dates.
--### Many sites will not have to modify this code.
--### Only make changes if you require special logic for these variables. 
--###
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################



--------------------------------------------------------------------------------
-- Create a list of all COVID-19 test results.
--------------------------------------------------------------------------------
--drop table fource_covid_tests;
create table fource_covid_tests (
	patient_num int not null,
	test_result varchar(10) not null,
	test_date date not null
);

alter table fource_covid_tests add primary key (patient_num, test_result, test_date);

insert into fource_covid_tests
	select distinct f.patient_num, m.code, trunc(start_date)
		from @crcSchema.observation_fact f --with (nolock)
			inner join fource_code_map m
				on f.concept_cd = m.local_code and m.code in ('covidpos','covidneg','covidU071');
commit;
--select * from fource_covid_tests;
--------------------------------------------------------------------------------
-- Create a list of patient admission dates.
--------------------------------------------------------------------------------
--drop table fource_admissions;

create table fource_admissions (
	patient_num int not null,
	admission_date date not null,
	discharge_date date not null
); 

alter table fource_admissions add primary key (patient_num, admission_date, discharge_date);
insert into fource_admissions
	select distinct patient_num, cast(start_date as date), nvl(cast(end_date as date),'01-JAN-2199') -- a very future date for missing discharge dates
	from (
		-- Select by inout_cd
		select patient_num, trunc(start_date) start_date, trunc(end_date) end_date
			from @crcSchema.visit_dimension
			where trunc(start_date) >= (select trunc(eval_start_date) from fource_config where rownum = 1)
				and patient_num in (select patient_num from fource_covid_tests)
				and inout_cd in (select local_code from fource_code_map where code = 'inpatient_inout_cd')
		union all
		-- Select by location_cd
		select patient_num, trunc(start_date), trunc(end_date)
			from @crcSchema.visit_dimension v
			where trunc(start_date) >= (select trunc(eval_start_date) from fource_config where rownum = 1)
				and patient_num in (select patient_num from fource_covid_tests)
				and location_cd in (select local_code from fource_code_map where code = 'inpatient_location_cd')
		union all
		-- Select by concept_cd
		select f.patient_num, trunc(f.start_date), nvl(trunc(f.end_date),trunc(v.end_date))
			from @crcSchema.observation_fact f
				inner join @crcSchema.visit_dimension v
					on v.encounter_num=f.encounter_num and v.patient_num=f.patient_num
			where trunc(f.start_date) >= (select trunc(eval_start_date) from fource_config where rownum = 1)
				and f.patient_num in (select patient_num from fource_covid_tests)
				and f.concept_cd in (select local_code from fource_code_map where code = 'inpatient_concept_cd')
	) t;
commit;

--select * from FOURCE_ADMISSIONS;

--select * from fource_admissions;
-- remove vists that end before they start

--select 'Number of admissions with discharge before admission: ' || count(*) from fource_admissions where discharge_date < admission_date;

delete from fource_admissions where discharge_date < admission_date;

--------------------------------------------------------------------------------
-- Create a list of dates where patients were in the ICU.
--------------------------------------------------------------------------------
create table fource_icu (
	patient_num int not null,
	start_date date not null,
	end_date date not null
); 

alter table fource_icu add primary key (patient_num, start_date, end_date);
--truncate table fource_icu;
insert into fource_icu
		select distinct patient_num, cast(start_date as date), nvl(cast(end_date as date), '01-JAN-2199') -- a very future date for missing end dates
		from (
			-- Select by patient_dimension inout_cd
			select patient_num, trunc(start_date) start_date, trunc(end_date) end_date
				from @crcSchema.visit_dimension
				where trunc(start_date) >= (select trunc(eval_start_date) from fource_config where rownum = 1)
					and patient_num in (select patient_num from fource_covid_tests)
					and inout_cd in (select local_code from fource_code_map where code = 'icu_inout_cd')
			union all
			-- Select by location_cd
			select patient_num, trunc(start_date) start_date, trunc(end_date) end_date --***** SOMEONE PLEASE AUDIT THIS SECTION******
				from @crcSchema.visit_dimension v
				where trunc(start_date) >= (select trunc(eval_start_date) from fource_config where rownum = 1)
					and patient_num in (select patient_num from fource_covid_tests)
					and location_cd in (select local_code from fource_code_map where code = 'icu_location_cd')
			union all
			-- Select by concept_cd
			select f.patient_num, trunc(f.start_date) start_date, nvl(trunc(f.end_date),trunc(v.end_date)) end_date
				from @crcSchema.observation_fact f
					inner join @crcSchema.visit_dimension v
						on v.encounter_num=f.encounter_num and v.patient_num=f.patient_num
				where trunc(f.start_date) >= (select trunc(eval_start_date) from fource_config where rownum = 1)
					and f.patient_num in (select patient_num from fource_covid_tests)
					and f.concept_cd in (select local_code from fource_code_map where code = 'icu_concept_cd')
            union all
            -- Select by location_cd in observation_fact table
            -- If you have an external table that has the local location_cd for ICU units use this block
            -- Need to be able to clean up epic encounters vs visits - is that in the analysis or later in the script
            select distinct f.patient_num, trunc(f.start_date) start_date, 
                case when trunc(f.end_date)> trunc(v.end_date)  then trunc(f.end_date)
                    else nvl(trunc(v.end_date), '01-JAN-2199') end end_date
				from @crcSchema.observation_fact f
					inner join @crcSchema.visit_dimension v
						on v.encounter_num=f.encounter_num and v.patient_num=f.patient_num
                    inner join fource_icu_location l on l.location_cd = f.location_cd
				where trunc(f.start_date) >= (select trunc(eval_start_date) from fource_config where rownum = 1)
					and f.patient_num in (select patient_num from fource_covid_tests)
                    order by patient_num, start_date
					--and f.concept_cd in (select local_code from fource_code_map where code = 'icu_fact_location_cd') --**** TODO: CHECK SHOULD THIS BE CONDITIONAL MICHELE FIX THIS 
       ) t
        where (select icu_data_available from fource_config where rownum = 1) = 1;
commit;

delete from fource_icu where trunc(end_date) < trunc(start_date);

--------------------------------------------------------------------------------
-- Create a list of dates when patients died.
--------------------------------------------------------------------------------
--drop table fource_death;
create table fource_death (
	patient_num int not null,
	death_date date not null
);

alter table fource_death add primary key (patient_num);

-- The death_date is estimated later in the SQL if it is null here.
insert into fource_death
        select patient_num, death_date from (
		select patient_num, nvl(death_date,'01-JAN-1900') death_date 
		from @crcSchema.patient_dimension
		where (death_date is not null or vital_status_cd in ('Y', 'DEM|VITAL STATUS:D'))
			and patient_num in (select patient_num from fource_covid_tests)       
            )t
    where (select death_data_available from fource_config where rownum = 1) = 1
;
commit;
--TODO: Check this logic again
--select patient_num, nvl(death_date,'01-JAN-1900') 
--		from patient_dimension
--		where (death_date is not null or vital_status_cd in ('Y', 'DEM|VITAL STATUS:D'))
--			and patient_num in (select patient_num from fource_covid_tests);

--select patient_num, nvl(death_date,'01-JAN-1900') 
--		from patient_dimension
--		where 1 in (select 1 from dual);
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--###
--### Setup the cohorts and retrieve the clinical data for the patients
--### (Most sites will not have to modify any SQL beyond this point)
--###
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################



--******************************************************************************
--******************************************************************************
--*** Setup the cohorts
--******************************************************************************
--******************************************************************************


--------------------------------------------------------------------------------
-- Get the earliest positive and earliest negative COVID-19 test results.
--------------------------------------------------------------------------------
--drop table fource_first_covid_tests;
create table fource_first_covid_tests (
	patient_num int not null,
	first_pos_date date,
	first_neg_date date,
	first_U071_date date
);

alter table fource_first_covid_tests add primary key (patient_num); 

insert into fource_first_covid_tests
	select patient_num,
			min(case when test_result='covidpos' then test_date else null end),
			min(case when test_result='covidneg' then test_date else null end),
			min(case when test_result='covidU071' then test_date else null end)
		from fource_covid_tests
		group by patient_num;
commit;


--------------------------------------------------------------------------------
-- Get the list of patients who will be in the cohorts.
-- By default, these will be patients who had an admission between 7 days before
--   and 14 days after their first covid positive test date.
--------------------------------------------------------------------------------
--drop table fource_cohort_patients;
create table fource_cohort_patients (
	cohort varchar(50) not null,
	patient_num int not null,
	admission_date date not null,
	source_data_updated_date date not null,
	severe int not null,
	severe_date date,
	death_date date
);

alter table fource_cohort_patients add primary key (patient_num, cohort);

--select * from fource_cohort_config;
insert into fource_cohort_patients (cohort, patient_num, admission_date, source_data_updated_date, severe)
	select c.cohort, t.patient_num, t.admission_date, c.source_data_updated_date, 0
	from fource_cohort_config c,
		(
			select t.patient_num, min(a.admission_date) admission_date
			from fource_first_covid_tests t
				inner join fource_admissions a
					on t.patient_num=a.patient_num
						--and datediff(dd,t.first_pos_date,a.admission_date) between @blackout_days_before and @blackout_days_after
                        and trunc(a.admission_date) - trunc(t.first_pos_date) between -7 and 14

			where t.first_pos_date is not null
			group by t.patient_num
		) t
	where c.cohort like 'PosAdm%'
		and trunc(t.admission_date) >= trunc(nvl(c.earliest_adm_date,t.admission_date))
		and trunc(t.admission_date) <= trunc(nvl(c.latest_adm_date,t.admission_date))
		and trunc(t.admission_date) <= trunc(nvl(c.source_data_updated_date,t.admission_date));
commit;
--select * from fource_cohort_patients;

--------------------------------------------------------------------------------
-- Add optional cohorts that contain all patients tested for COVID-19
--------------------------------------------------------------------------------
-- Create cohorts for patients who were admitted
insert into fource_cohort_config
        select * from (
		-- Patients with a U07.1 code, no recorded positive test result, and were admitted
		select replace(c.cohort,'PosAdm','U071Adm'), 
				g.include_extra_cohorts_phase1, g.include_extra_cohorts_phase2,
				c.source_data_updated_date, c.earliest_adm_date, c.latest_adm_date
			from fource_cohort_config c cross apply fource_config g
			where c.cohort like 'PosAdm%'
		-- Patients who have no U07.1 code, no recorded positive test result, a negative test result, and were admitted
		union all
		select replace(c.cohort,'PosAdm','NegAdm'), 
				g.include_extra_cohorts_phase1, g.include_extra_cohorts_phase2,
				c.source_data_updated_date, c.earliest_adm_date, c.latest_adm_date
			from fource_cohort_config c cross apply fource_config g
			where c.cohort like 'PosAdm%')
        where (select include_extra_cohorts_phase1 from fource_config where rownum = 1) = 1 
        or (select include_extra_cohorts_phase2 from fource_config where rownum = 1) = 1;
commit;
--select * from fource_cohort_config;

-- Add the patients for those cohorts
insert into fource_cohort_patients (cohort, patient_num, admission_date, source_data_updated_date, severe)
    select * from (
		select c.cohort, t.patient_num, t.admission_date, c.source_data_updated_date, 0
		from fource_cohort_config c,
			(
				select t.patient_num, 'U071Adm' cohort, min(a.admission_date) admission_date
					from fource_first_covid_tests t
						inner join fource_admissions a
							on t.patient_num=a.patient_num
								--and datediff(dd,t.first_U071_date,a.admission_date) between @blackout_days_before and @blackout_days_after
                                and trunc(a.admission_date) - trunc(t.first_U071_date) between -7 and 14
					where t.first_U071_date is not null and t.first_pos_date is null
					group by t.patient_num
                union all
				select t.patient_num, 'NegAdm' cohort, min(a.admission_date) admission_date
					from fource_first_covid_tests t
						inner join fource_admissions a
							on t.patient_num=a.patient_num
								--and datediff(dd,t.first_neg_date,a.admission_date) between @blackout_days_before and @blackout_days_after
                                and trunc(a.admission_date) - trunc(t.first_neg_date) between -7 and 14
					where t.first_neg_date is not null and t.first_U071_date is null and t.first_pos_date is null
					group by t.patient_num
			) t
		where c.cohort like t.cohort || '%'
			and trunc(t.admission_date) >= trunc(nvl(c.earliest_adm_date,t.admission_date))
			and trunc(t.admission_date) <= trunc(nvl(c.latest_adm_date,t.admission_date))
			and trunc(t.admission_date) <= trunc(nvl(c.source_data_updated_date,t.admission_date))
        ) t
    where (select include_extra_cohorts_phase1 from fource_config where rownum = 1) = 1 
        or (select include_extra_cohorts_phase2 from fource_config where rownum = 1) = 1;
commit;
-- Create cohorts for patients who were not admitted
insert into fource_cohort_config
		select replace(c.cohort,'Adm','NotAdm'), 
				g.include_extra_cohorts_phase1, g.include_extra_cohorts_phase2,
				c.source_data_updated_date, c.earliest_adm_date, c.latest_adm_date
			from fource_cohort_config c cross apply fource_config g
			where c.cohort like 'PosAdm%' or c.cohort like 'NegAdm%' or c.cohort like 'U071Adm%';
commit;

-- Add the patients for those cohorts using the test or diagnosis date as the "admission" (index) date
insert into fource_cohort_patients (cohort, patient_num, admission_date, source_data_updated_date, severe)
		select c.cohort, t.patient_num, t.first_pos_date, c.source_data_updated_date, 0
			from fource_cohort_config c
				cross join fource_first_covid_tests t
			where c.cohort like 'PosNotAdm%'
				and t.first_pos_date is not null
				and trunc(t.first_pos_date) >= trunc(nvl(c.earliest_adm_date,t.first_pos_date))
				and trunc(t.first_pos_date) <= trunc(nvl(c.latest_adm_date,t.first_pos_date))
				and trunc(t.first_pos_date) <= trunc(nvl(c.source_data_updated_date,t.first_pos_date))
				and t.patient_num not in (select patient_num from fource_cohort_patients)
		union all
		select c.cohort, t.patient_num, t.first_U071_date, c.source_data_updated_date, 0
			from fource_cohort_config c
				cross join fource_first_covid_tests t
			where c.cohort like 'U071NotAdm%'
				and t.first_pos_date is null
				and t.first_U071_date is not null
				and trunc(t.first_U071_date) >= trunc(nvl(c.earliest_adm_date,t.first_U071_date))
				and trunc(t.first_U071_date) <= trunc(nvl(c.latest_adm_date,t.first_U071_date))
				and trunc(t.first_U071_date) <= trunc(nvl(c.source_data_updated_date,t.first_U071_date))
				and t.patient_num not in (select patient_num from fource_cohort_patients)
		union all
		select c.cohort, t.patient_num, t.first_neg_date, c.source_data_updated_date, 0
			from fource_cohort_config c
				cross join fource_first_covid_tests t
			where c.cohort like 'NegNotAdm%'
				and t.first_pos_date is null
				and t.first_U071_date is null
				and t.first_neg_date is not null
				and trunc(t.first_neg_date) >= trunc(nvl(c.earliest_adm_date,t.first_neg_date))
				and trunc(t.first_neg_date) <= trunc(nvl(c.latest_adm_date,t.first_neg_date))
				and trunc(t.first_neg_date) <= trunc(nvl(c.source_data_updated_date,t.first_neg_date))
				and t.patient_num not in (select patient_num from fource_cohort_patients);

--------------------------------------------------------------------------------
-- Add additional custom cohorts here
--------------------------------------------------------------------------------

-- My custom cohorts

commit;
--******************************************************************************
--******************************************************************************
--*** Create a table of patient observations
--******************************************************************************
--******************************************************************************


-- Get a distinct list of patients
create table fource_patients (
	patient_num int not null,
	first_admission_date date not null
);
alter table fource_patients add primary key (patient_num);
insert into fource_patients
	select patient_num, min(admission_date)
		from fource_cohort_patients
		group by patient_num;
commit;
-- Create the table to store the observations
create table fource_observations (
	cohort varchar(50) not null,
	patient_num int not null,
	severe int not null,
	concept_type varchar(50) not null,
	concept_code varchar(50) not null,
	calendar_date date not null,
	days_since_admission int not null,
	value numeric(18,5) not null,
	logvalue numeric(18,10) not null
);
alter table fource_observations add primary key (cohort, patient_num, concept_type, concept_code, days_since_admission);

--------------------------------------------------------------------------------
-- Add covid tests
--------------------------------------------------------------------------------
insert into fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select distinct
		p.cohort,
		p.patient_num,
		p.severe,
		'COVID-TEST',
		t.test_result,
		t.test_date,
		trunc(t.test_date) - trunc(p.admission_date),
		-999,
		-999
 	from fource_cohort_patients p
		inner join fource_covid_tests t
			on p.patient_num=t.patient_num;
commit;

--------------------------------------------------------------------------------
-- Add children who develop MIS-C
--------------------------------------------------------------------------------
insert into fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select distinct
		p.cohort,
		p.patient_num,
		p.severe,
		'COVID-MISC',
		'misc',
		cast(f.misc_date as date),
		trunc(cast(f.misc_date as date)) - trunc(p.admission_date),
		-999,
		-999
 	from fource_cohort_patients p
		inner join fource_misc f --with (nolock)
			on p.patient_num=f.patient_num;
create index fource_cohort_patients_ndx on fource_cohort_patients(patient_num);
--------------------------------------------------------------------------------
-- Add diagnoses (ICD9) going back 365 days from admission 
--------------------------------------------------------------------------------
insert into fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select distinct
		p.cohort,
		p.patient_num,
		p.severe,
		'DIAG-ICD9',
		substr(f.concept_cd, instr(f.concept_cd,':')+1),
		trunc(f.start_date),
		trunc(f.start_date) - trunc(p.admission_date),
		-999,
		-999
 	from @crcSchema.observation_fact f --with (nolock)
		inner join fource_cohort_patients p 
			on f.patient_num=p.patient_num
				--and cast(trunc(f.start_date) as date) between dateadd(dd,@lookback_days,p.admission_date) and p.source_data_updated_date
                and trunc(f.start_date) between trunc(p.admission_date)-365 and trunc(p.source_data_updated_date)
	where f.concept_cd like (select code_prefix_icd9cm || '%' from fource_config where rownum = 1);-- and code_prefix_icd9cm <>'';
commit;    

--------------------------------------------------------------------------------
-- Add diagnoses (ICD10) going back 365 days
--------------------------------------------------------------------------------
insert into fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select distinct
		p.cohort,
		p.patient_num, 
		nvl(p.severe,0),
		'DIAG-ICD10',
		substr(f.concept_cd, instr(f.concept_cd,':')+1),
		trunc(f.start_date),
		trunc(f.start_date) - trunc(p.admission_date),
		-999,
		-999
 	from @crcSchema.observation_fact f --with (nolock)
		inner join fource_cohort_patients p 
			on f.patient_num=p.patient_num 
				--and cast(trunc(f.start_date) as date) between dateadd(dd,@lookback_days,p.admission_date) and p.source_data_updated_date
                and trunc(f.start_date) between trunc(p.admission_date)-365 and trunc(p.source_data_updated_date)
	where f.concept_cd like (select code_prefix_icd10cm || '%' from fource_config where rownum = 1);-- and code_prefix_icd10cm <>'';
commit;
--select count(distinct patient_num) from fource_observations; --293601
--------------------------------------------------------------------------------
-- Add medications (Med Class) going back 365 days
--------------------------------------------------------------------------------
insert into fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select distinct
		p.cohort,
		p.patient_num,
		p.severe,
		'MED-CLASS',
		m.med_class,	
		trunc(f.start_date),
		trunc(f.start_date) - trunc(p.admission_date),
		-999,
		-999
	from fource_med_map m
		inner join @crcSchema.observation_fact f --with (nolock)
			on f.concept_cd = m.local_med_code
		inner join fource_cohort_patients p 
			on f.patient_num=p.patient_num 
               and trunc(f.start_date) between trunc(p.admission_date)-365 and trunc(p.source_data_updated_date);
commit;

--and cast(trunc(f.start_date) as date) between dateadd(dd,@lookback_days,p.admission_date) and p.source_data_updated_date

--------------------------------------------------------------------------------
-- Add labs (LOINC) going back 60 days (two months)
--------------------------------------------------------------------------------
insert into fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select p.cohort,
		p.patient_num,
		p.severe,
		'LAB-LOINC',		
		l.fource_loinc,
		trunc(f.start_date),
		trunc(f.start_date) - trunc(p.admission_date),
		avg(f.nval_num*l.scale_factor),
		ln(avg(f.nval_num*l.scale_factor) + 0.5) -- natural log (ln), not log base 10; using log(avg()) rather than avg(log()) on purpose
	from fource_lab_map l
		inner join @crcSchema.observation_fact f --with (nolock)
			on f.concept_cd=l.local_lab_code and nvl(nullif(f.units_cd,''),'DEFAULT')=l.local_lab_units
		inner join fource_cohort_patients p 
			on f.patient_num=p.patient_num
	where l.local_lab_code is not null
		and f.nval_num is not null
		and f.nval_num >= 0
		and trunc(f.start_date) between trunc(p.admission_date)-60 and trunc(p.source_data_updated_date) --@lab lookback days
	group by p.cohort, p.patient_num, p.severe, p.admission_date, trunc(f.start_date), l.fource_loinc;
commit;

--------------------------------------------------------------------------------
-- Add procedures (Proc Groups) going back 365 days
--------------------------------------------------------------------------------
--select * from fource_proc_map;
insert into fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select distinct
		p.cohort,
		p.patient_num,
		p.severe,
		'PROC-GROUP',
		x.proc_group,
		trunc(f.start_date),
		trunc(f.start_date) - trunc(p.admission_date),
		-999,
		-999
 	from fource_proc_map x
		inner join @crcSchema.observation_fact f --with (nolock)
			on f.concept_cd = x.local_proc_code
		inner join fource_cohort_patients p 
			on f.patient_num=p.patient_num 
	where x.local_proc_code is not null
          and trunc(f.start_date) between trunc(p.admission_date)-365 and trunc(p.source_data_updated_date);
commit;

--------------------------------------------------------------------------------
-- Flag observations that contribute to the disease severity definition
--------------------------------------------------------------------------------
--test select * from fource_observations where concept_code = 'ARDS';
insert into fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	-- Any PaCO2 or PaO2 lab test
	select cohort, patient_num, severe, 'SEVERE-LAB' concept_type, 'BloodGas' concept_code, calendar_date, days_since_admission, avg(value), avg(logvalue)
		from fource_observations
		where concept_type='LAB-LOINC' and concept_code in ('2019-8','2703-7')
		group by cohort, patient_num, severe, calendar_date, days_since_admission
	-- Acute respiratory distress syndrome (diagnosis)
	union all
	select distinct cohort, patient_num, severe, 'SEVERE-DIAG' concept_type, 'ARDS' concept_code, calendar_date, days_since_admission, value, logvalue
		from fource_observations
		where (concept_type='DIAG-ICD9' and concept_code in ('518.82','51882'))
			or (concept_type='DIAG-ICD10' and concept_code in ('J80'))
	-- Ventilator associated pneumonia (diagnosis)
	union all
	select distinct cohort, patient_num, severe, 'SEVERE-DIAG' concept_type, 'VAP' concept_code, calendar_date, days_since_admission, value, logvalue
		from fource_observations
		where (concept_type='DIAG-ICD9' and concept_code in ('997.31','99731'))
			or (concept_type='DIAG-ICD10' and concept_code in ('J95.851','J95851'));

commit;
--******************************************************************************
--******************************************************************************
--*** Determine which patients had severe disease or died
--******************************************************************************
--******************************************************************************


--------------------------------------------------------------------------------
-- Flag the patients who had severe disease with 30 days of admission.
--------------------------------------------------------------------------------
--test select * from fource_cohort_patients where severe = 0;
update fource_cohort_patients p set severe = 1, 
    severe_date=(select min(f.calendar_date)
                    from fource_observations f
                    where f.days_since_admission between 0 and 30 and f.cohort=p.cohort and f.patient_num=p.patient_num 
                        and (
					-- Any severe lab or diagnosis
					(f.concept_type in ('SEVERE-LAB','SEVERE-DIAG'))
					-- Any severe medication
					or (f.concept_type='MED-CLASS' and f.concept_code in ('SIANES','SICARDIAC'))
					-- Any severe procedure
					or (f.concept_type='PROC-GROUP' and f.concept_code in ('SupplementalOxygenSevere','ECMO'))
				)
			group by f.cohort, f.patient_num
        ) 
    where exists (
    select min(f.calendar_date) from fource_observations f where f.cohort=p.cohort and f.patient_num=p.patient_num and 
        f.days_since_admission between 0 and 30
                    and (
					-- Any severe lab or diagnosis
					(f.concept_type in ('SEVERE-LAB','SEVERE-DIAG'))
					-- Any severe medication
					or (f.concept_type='MED-CLASS' and f.concept_code in ('SIANES','SICARDIAC'))
					-- Any severe procedure
					or (f.concept_type='PROC-GROUP' and f.concept_code in ('SupplementalOxygenSevere','ECMO'))
				)
    			group by f.cohort, f.patient_num
            );
commit;

-- Flag the severe patients in the observations table
update fource_observations f
set f.severe=1
where exists(select patient_num,cohort
	     from fource_cohort_patients cwhere c.severe=0 and 
f.patient_num = c.patient_num and f.cohort = c.cohort);

--------------------------------------------------------------------------------
-- Add death dates to patients who have died.
--------------------------------------------------------------------------------
--if exists (select * from fource_config where death_data_available = 1)
--begin;
	-- Add the original death date.
	merge into fource_cohort_patients c
    using (
        select p.patient_num,
			min(case when p.death_date > nvl(c.severe_date,c.admission_date) 
			then cast(p.death_date as date)
			else nvl(c.severe_date,c.admission_date) end) as death_date
		from fource_cohort_patients c
			inner join fource_death p
				on p.patient_num = c.patient_num 
        group by p.patient_num) d
        on (c.patient_num = d.patient_num and 
        (select death_data_available from fource_config where rownum = 1)= 1)
        WHEN MATCHED THEN
        UPDATE SET c.death_date = d.death_date;

commit;

 -- Check that there aren't more recent facts for the deceased patients.
 -- ****Be careful with this - if you trust your death data omit this - 
 -- ****Be sure that the future facts aren't orders, future appointmnents or late arriving lab results
 
	merge into fource_cohort_patients c
	using (	select p.patient_num, cast(max(f.calendar_date) as date) death_date
				from fource_cohort_patients p
					inner join fource_observations f
						on f.cohort=p.cohort and f.patient_num=p.patient_num
				where p.death_date is not null and f.calendar_date > p.death_date
				group by p.cohort, p.patient_num
			) d 
        on (c.patient_num = d.patient_num and 
        (select death_data_available from fource_config where rownum = 1)= 1)
        WHEN MATCHED THEN
        UPDATE SET c.death_date = d.death_date;

	-- Make sure the death date is not after the source data updated date
	update fource_cohort_patients
		set death_date = null
		where death_date > source_data_updated_date
        and (select death_data_available from fource_config where rownum = 1)= 1;
commit;


--******************************************************************************
--******************************************************************************
--*** For each cohort, create a list of dates since the first case.
--******************************************************************************
--******************************************************************************


create table fource_date_list (
	cohort varchar(50) not null,
	d date not null
);

alter table fource_date_list add primary key (cohort, d);

insert into fource_date_list select * from (
    with n as (
        select 0 n from dual union all select 1 from dual union all select 2 from dual union all select 3 from dual union all select 4 
        from dual union all select 5 from dual union all select 6 from dual union all select 7 from dual union all select 8 from dual union all select 9 from dual
    )
	select l.cohort, d
	from (
		--select cohort, nvl(cast(dateadd(dd,a.n+10*b.n+100*c.n,p.s) as date),'01-JAN-2020') d
        select cohort, nvl((p.min_admit_date-a.n+10*b.n+100*c.n),'01-JAN-2020') d
		from (
			select cohort, min(admission_date) min_admit_date 
			from fource_cohort_patients 
			group by cohort
		) p cross join n a cross join n b cross join n c
	) l inner join fource_cohort_config f on l.cohort=f.cohort
	where d <= f.source_data_updated_date    
    );
commit;


--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--###
--### Assemble data for Phase 2 local PATIENT-LEVEL tables
--###
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################



--------------------------------------------------------------------------------
-- LocalPatientClinicalCourse: Status by number of days since admission
--------------------------------------------------------------------------------
--select * from fource_LocalPatientClinicalCourse;
--drop table fource_LocalPatientClinicalCourse;
create table fource_LocalPatientClinicalCourse (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	patient_num int not null,
	days_since_admission int not null,
	calendar_date date not null,
	in_hospital int not null,
	severe int not null,
	in_icu int not null,
	dead int not null
);

alter table fource_LocalPatientClinicalCourse add primary key (cohort, patient_num, days_since_admission, siteid);
-- Get the list of dates and flag the ones where the patients were severe or deceased
insert into fource_LocalPatientClinicalCourse 
    (siteid, cohort, patient_num, days_since_admission, calendar_date, in_hospital, severe, in_icu, dead)
	select (select siteid from fource_config where rownum = 1) siteid, 
        p.cohort, p.patient_num, 
		trunc(d.d)-trunc(p.admission_date) days_since_admission,
		d.d calendar_date,
		0 in_hospital,
		max(case when p.severe=1 and trunc(d.d)>=trunc(p.severe_date) then 1 else 0 end) severe,
		max(case when (select icu_data_available from fource_config where rownum = 1)=0 then -999 else 0 end) in_icu,
		max(case when (select death_data_available from fource_config where rownum = 1)=0 then -999 
			when p.death_date is not null and trunc(d.d) >= trunc(p.death_date) then 1 
			else 0 end) dead
--	from fource_config x
		from fource_cohort_patients p
		inner join fource_date_list d
			on p.cohort=d.cohort and trunc(d.d)>=trunc(p.admission_date)
	group by p.cohort, p.patient_num, p.admission_date, d.d;
commit; -- 5 minutes    
    

-- Flag the days when the patients was in the hospital
merge into fource_LocalPatientClinicalCourse p
	using (
    select distinct p.patient_num,  p.calendar_date
    from fource_LocalPatientClinicalCourse p 
    inner join fource_admissions a on a.patient_num = p.patient_num
        and trunc(a.admission_date)>= trunc(p.calendar_date)-days_since_admission --TODO: Check the logic again - MICHELE IS THE SUBTRACTION CORRECT
		and trunc(a.admission_date)<=trunc(p.calendar_date)
		and a.discharge_date>=trunc(p.calendar_date) 
        )d
    on (d.patient_num=p.patient_num and d.calendar_date=p.calendar_date)
    when matched then
        update set p.in_hospital=1;
commit;

-- Flag the days when the patient was in the ICU, making sure the patient was also in the hospital on those days
merge into fource_LocalPatientClinicalCourse p
    using ( 
    --with pt_icu as (
    select patient_num,  calendar_date, in_hospital, in_icu from (
    select distinct p.patient_num,  p.calendar_date, p.in_hospital, p.in_icu
            from fource_LocalPatientClinicalCourse p
			inner join fource_icu i
				on i.patient_num=p.patient_num 
					and trunc(i.start_date)>=trunc(p.calendar_date)-days_since_admission
					and trunc(i.start_date)<=trunc(p.calendar_date)
					and trunc(i.end_date)>=trunc(p.calendar_date)
                    and (select icu_data_available from fource_config where rownum=1)=1 ))d
                    --group by patient_num,  calendar_date, in_hospital ;--order by patient_num, calendar_date);
                --select patient_num, calendar_date, in_hospital, in_icu from pt_icu )d
    on (d.patient_num=p.patient_num and d.calendar_date=p.calendar_date)
    when matched then
        update set p.in_icu=p.in_hospital;
commit;
--2005 rows 70032
--select count(distinct patient_num) from fource_LocalPatientClinicalCourse where in_icu = 1; --52 
--------------------------------------------------------------------------------
-- LocalPatientSummary: Dates, outcomes, age, and sex
--------------------------------------------------------------------------------
--drop table fource_LocalPatientSummary;
create table fource_LocalPatientSummary (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	patient_num int not null,
	admission_date date not null,
	source_data_updated_date date not null,
	days_since_admission int not null,
	last_discharge_date date not null,
	still_in_hospital int not null,
	severe_date date not null,
	severe int not null,
	icu_date date not null,
	icu int not null,
	death_date date not null,
	dead int not null,
	age_group varchar(50) not null,
	age int not null,
	sex varchar(50) not null
);
alter table fource_LocalPatientSummary add primary key (cohort, patient_num, siteid);
-- Get the admission, severe, and death dates; and age and sex.
insert into fource_LocalPatientSummary
	select (select siteid from fource_config where rownum=1), c.cohort, c.patient_num, 
        c.admission_date,
		c.source_data_updated_date,
		trunc(c.source_data_updated_date)-trunc(c.admission_date) days_since_admission,
		'01-JAN-1900' last_discharge_date,
		0 still_in_hospital,
		nvl(c.severe_date,'01-JAN-1900') severe_date,
		c.severe, 
		'01-JAN-1900' icu_date,
		(case when (select icu_data_available from fource_config where rownum=1)=0 then -999 else 0 end) in_icu,
		nvl(c.death_date,'01-JAN-1900') death_date,
		(case when (select death_data_available from fource_config where rownum=1)=0 then -999 when c.death_date is not null then 1 else 0 end) dead,
		(case
			when p.age_in_years_num between 0 and 2 then '00to02'
			when p.age_in_years_num between 3 and 5 then '03to05'
			when p.age_in_years_num between 6 and 11 then '06to11'
			when p.age_in_years_num between 12 and 17 then '12to17'
			when p.age_in_years_num between 18 and 20 then '18to20'
			when p.age_in_years_num between 21 and 25 then '21to25'
			when p.age_in_years_num between 26 and 49 then '26to49'
			when p.age_in_years_num between 50 and 69 then '50to69'
			when p.age_in_years_num between 70 and 79 then '70to79'
			when p.age_in_years_num >= 80 then '80plus'
			else 'other' end) age_group,
		(case when p.age_in_years_num is null then -999 when p.age_in_years_num<0 then -999 else age_in_years_num end) age,
		nvl(substr(m.code,13,99),'other')
	from fource_cohort_patients c
		left outer join @crcSchema.patient_dimension p
			on p.patient_num=c.patient_num
		left outer join fource_code_map m
			on p.sex_cd = m.local_code
				and m.code in ('sex_patient:male','sex_patient:female');
commit;
--select * from fource_LocalPatientSummary;

-- Update sex if sex stored in observation_fact table
merge into fource_LocalPatientSummary s
using (select p.sex, p.patient_num
	   from fource_LocalPatientSummary s
		inner join (
			select patient_num, (case when male=1 then 'male' else 'female' end) sex
			from (
				select patient_num,
					max(case when m.code='sex_fact:male' then 1 else 0 end) male,
					max(case when m.code='sex_fact:female' then 1 else 0 end) female
				from @crcSchema.observation_fact f --with (nolock)
					inner join fource_code_map m
						on f.concept_cd=m.local_code
							and m.code in ('sex_fact:male','sex_fact:female')
				group by patient_num
			) t
			where male+female=1
		) p on s.patient_num = p.patient_num )x
    on (s.patient_num = x.patient_num )
    when matched then
	update set s.sex = (case when s.sex='other' then x.sex when s.sex<>x.sex then 'other' else s.sex end);
commit;
-- Get the last discharge date and whether the patient is still in the hospital as of the source_data_updated_date.
	merge into fource_LocalPatientSummary s
	using ( select p.cohort, p.patient_num, max(a.discharge_date) last_discharge_date
			from fource_LocalPatientSummary p
				inner join fource_admissions a
					on a.patient_num=p.patient_num 
						and trunc(a.admission_date)>=trunc(p.admission_date)
			group by p.cohort, p.patient_num
          ) x 
        on (s.cohort=x.cohort and s.patient_num=x.patient_num) 
        when matched then
        update set s.last_discharge_date = (case when x.last_discharge_date>s.source_data_updated_date then to_date('01-JAN-1900','DD-MON-YYYY') 
                                            else x.last_discharge_date end),
                   s.still_in_hospital = (case when x.last_discharge_date>s.source_data_updated_date then 1 else 0 end);
commit;
--select * from fource_LocalPatientClinicalCourse where in_icu = 1;
-- Get earliest ICU date for patients who were in the ICU.
merge into fource_LocalPatientSummary s
      using (
			select cohort, patient_num, min(calendar_date) icu_date
					from fource_LocalPatientClinicalCourse
					where in_icu=1
					group by cohort, patient_num
			) x
        on (s.cohort=x.cohort and s.patient_num=x.patient_num and (select icu_data_available from fource_config where rownum = 1)=1)
        when matched then
        update set s.icu_date = x.icu_date,
                   s.icu = 1;
commit;
--------------------------------------------------------------------------------
-- LocalPatientObservations: Diagnoses, procedures, medications, and labs
--------------------------------------------------------------------------------
--drop table fource_LocalPatientObservations;
create table fource_LocalPatientObservations (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	patient_num int not null,
	days_since_admission int not null,
	concept_type varchar(50) not null,
	concept_code varchar(50) not null,
	value numeric(18,5) not null
);
alter table fource_LocalPatientObservations add primary key (cohort, patient_num, days_since_admission, concept_type, concept_code, siteid);
insert into fource_LocalPatientObservations
	select (select siteid from fource_config where rownum = 1), 
    cohort, patient_num, days_since_admission, concept_type, concept_code, value
	from fource_observations;
commit;
--------------------------------------------------------------------------------
-- LocalPatientRace: local and 4CE race code(s) for each patient
--------------------------------------------------------------------------------
--drop table fource_LocalPatientRace;
create table fource_LocalPatientRace (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	patient_num int not null,
	race_local_code varchar(500) not null,
	race_4ce varchar(100) not null
);
alter table fource_LocalPatientRace add primary key (cohort, patient_num, race_local_code, siteid);
insert into fource_LocalPatientRace
		select distinct (select siteid from fource_config where rownum = 1) siteid, cohort, patient_num, race_local_code, race_4ce
		from (
			-- Race from the patient_dimension table
			select c.cohort, c.patient_num, m.local_code race_local_code, substr(m.code,14,999) race_4ce
				from fource_cohort_patients c
					inner join @crcSchema.patient_dimension p
						on p.patient_num=c.patient_num
					inner join fource_code_map m
						on p.race_cd = m.local_code
							and m.code like 'race_patient:%'
			union all
			-- Race from the observation_fact table
			select c.cohort, c.patient_num, m.local_code race_local_code, substr(m.code,11,999) race_4ce
				from fource_cohort_patients c
					inner join @crcSchema.observation_fact p --with (nolock)
						on p.patient_num=c.patient_num
					inner join fource_code_map m
						on p.concept_cd = m.local_code
							and m.code like 'race_fact:%'
		) t
        where (select race_data_available from fource_config where rownum =1)=1;
commit;


--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--###
--### Assemble data for Phase 2 local AGGREGATE COUNT tables.
--### These are the local versions without obfuscation.
--###
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################



--------------------------------------------------------------------------------
-- LocalCohorts
--------------------------------------------------------------------------------
--drop table fource_LocalCohorts;
create table fource_LocalCohorts (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	include_in_phase1 int not null,
	include_in_phase2 int not null,
	source_data_updated_date date not null,
	earliest_adm_date date not null,
	latest_adm_date date not null
);
alter table fource_LocalCohorts add primary key (cohort, siteid);
insert into fource_LocalCohorts
	select (select siteid from fource_config where rownum = 1) siteid, cohort, include_in_phase1, include_in_phase2, source_data_updated_date, earliest_adm_date, latest_adm_date 
	from fource_cohort_config;
commit;
--------------------------------------------------------------------------------
-- LocalDailyCounts
--------------------------------------------------------------------------------
--drop table fource_LocalDailyCounts;
create table fource_LocalDailyCounts (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	calendar_date date not null,
	cumulative_pts_all int not null,
	cumulative_pts_icu int not null,
	cumulative_pts_dead int not null,
	cumulative_pts_severe int not null,
	cumulative_pts_severe_icu int not null,
	cumulative_pts_severe_dead int not null,
	pts_in_hosp_on_this_date int not null,
	pts_in_icu_on_this_date int not null,
	pts_severe_in_hosp_on_date int not null,
	pts_severe_in_icu_on_date int not null
);
alter table fource_LocalDailyCounts add primary key (cohort, calendar_date, siteid);
-- Get daily counts, except for ICU

insert into fource_LocalDailyCounts 
	select (select siteid from fource_config where rownum = 1) siteid, cohort, calendar_date, 
		-- Cumulative counts
		count(*), 
		(case when x.icu_data_available=0 then -999 else 0 end),
		(case when x.death_data_available=0 then -999 else sum(dead) end),
		sum(severe), 
		(case when x.icu_data_available=0 then -999 else 0 end),
		(case when x.death_data_available=0 then -999 else sum(severe*dead) end),
		-- Counts on the calendar_date
		sum(in_hospital), 
		(case when x.icu_data_available=0 then -999 else sum(in_icu) end),
		sum(in_hospital*severe), 
		(case when x.icu_data_available=0 then -999 else sum(in_icu*severe) end)
	from fource_config x
		cross join fource_LocalPatientClinicalCourse c
	group by cohort, calendar_date, icu_data_available, death_data_available;
    commit;
    
-- Update daily counts based on the first time patients were in the ICU 
--TODO: MICHELE Make sure Griffin or someone else reviews this update
--select * from fource_LocalDailyCounts;
--select * from fource_LocalPatientSummary where icu_date >to_date('01-JAN-1900', 'DD-MON-YYYY') order by cohort, admission_date;
--**************TODO: MICHELE ERROR Unable to get stable rows in source*****************
/*merge into fource_LocalDailyCounts c
    using (
      select calendar_date, cohort, icu_date, cumm_daily_count from (
      select distinct d.calendar_date, d.cohort, a.icu_date, count(*) cumm_daily_count
            from fource_LocalDailyCounts d
            join fource_LocalPatientSummary a
            on  a.cohort=d.cohort  and a.icu_date>to_date('01-JAN-1900', 'DD-MON-YYYY') and a.icu_date<=d.calendar_date
            group by d.cohort,d.calendar_date, a.icu_date 
            )
            ) x
        on (x.cohort=c.cohort and x.calendar_date=c.calendar_date)
        when matched then
        	update set c.cumulative_pts_icu = x.cumm_daily_count;
         
            
            
select * from 				 fource_LocalPatientSummary a;

select * from visit_dimension where patient_num = 348143;
			cumulative_pts_severe_icu = (
				select count(*)
				from fource_LocalPatientSummary a
				where a.cohort=c.cohort and a.icu_date<=c.calendar_date and a.icu_date>'01-JAN-1900' and a.severe=1
			)
(select icu_data_available from fource_config where rownum=1)=1);


*/
--------------------------------------------------------------------------------
-- LocalClinicalCourse
--------------------------------------------------------------------------------
create table fource_LocalClinicalCourse (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	days_since_admission int not null,
	pts_all_in_hosp int not null,
	pts_all_in_icu int not null,
	pts_all_dead int not null,
	pts_severe_by_this_day int not null,
	pts_ever_severe_in_hosp int not null,
	pts_ever_severe_in_icu int not null,
	pts_ever_severe_dead int not null
);
alter table fource_LocalClinicalCourse add primary key (cohort, days_since_admission, siteid);
insert into fource_LocalClinicalCourse
	select  (select siteid from fource_config where rownum = 1) siteid, 
        c.cohort, c.days_since_admission, 
		sum(c.in_hospital), 
		(case when x.icu_data_available=0 then -999 else sum(c.in_icu) end), 
		(case when x.death_data_available=0 then -999 else sum(c.dead) end), 
		sum(c.severe),
		sum(c.in_hospital*p.severe), 
		(case when x.icu_data_available=0 then -999 else sum(c.in_icu*p.severe) end), 
		(case when x.death_data_available=0 then -999 else sum(c.dead*p.severe) end) 
	from fource_config x
		cross join fource_LocalPatientClinicalCourse c
		inner join fource_cohort_patients p
			on c.cohort=p.cohort and c.patient_num=p.patient_num
	group by c.cohort, c.days_since_admission, icu_data_available, death_data_available;
commit;
--------------------------------------------------------------------------------
-- LocalAgeSex
--------------------------------------------------------------------------------
--drop table fource_LocalAgeSex;
create table fource_LocalAgeSex (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	age_group varchar(20) not null,
	mean_age numeric(18,10) not null,
	sex varchar(10) not null,
	pts_all int not null,
	pts_ever_severe int not null
);
alter table fource_LocalAgeSex add primary key (cohort, age_group, sex, siteid);
insert into fource_LocalAgeSex
	select  (select siteid from fource_config where rownum = 1) siteid, cohort, age_group, nvl(avg(cast(nullif(age,-999) as numeric(18,10))),-999), sex, count(*), sum(severe)
		from fource_LocalPatientSummary
		group by cohort, age_group, sex
	union all
	select  (select siteid from fource_config where rownum = 1) siteid, cohort, 'all', nvl(avg(cast(nullif(age,-999) as numeric(18,10))),-999), sex, count(*), sum(severe)
		from fource_LocalPatientSummary
		group by cohort, sex
	union all
	select  (select siteid from fource_config where rownum = 1) siteid, cohort, age_group, nvl(avg(cast(nullif(age,-999) as numeric(18,10))),-999), 'all', count(*), sum(severe)
		from fource_LocalPatientSummary
		group by cohort, age_group
	union all
	select  (select siteid from fource_config where rownum = 1) siteid, cohort, 'all', nvl(avg(cast(nullif(age,-999) as numeric(18,10))),-999), 'all', count(*), sum(severe)
		from fource_LocalPatientSummary
		group by cohort;
commit;
--------------------------------------------------------------------------------
-- LocalLabs
--------------------------------------------------------------------------------
--drop table fource_LocalLabs;
create table fource_LocalLabs (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	loinc varchar(20) not null,
	days_since_admission int not null,
	pts_all int,
	mean_value_all numeric(18,5),
	stddev_value_all numeric(18,5),
	mean_log_value_all numeric(18,10),
	stddev_log_value_all numeric(18,10),
	pts_ever_severe int,
	mean_value_ever_severe numeric(18,5),
	stddev_value_ever_severe numeric(18,5),
	mean_log_value_ever_severe numeric(18,10),
	stddev_log_value_ever_severe numeric(18,10),
	pts_never_severe int,
	mean_value_never_severe numeric(18,5),
	stddev_value_never_severe numeric(18,5),
	mean_log_value_never_severe numeric(18,10),
	stddev_log_value_never_severe numeric(18,10)
); 
alter table fource_LocalLabs add primary key (cohort, loinc, days_since_admission, siteid);

insert into fource_LocalLabs
	select  (select siteid from fource_config where rownum = 1) siteid, cohort, concept_code, days_since_admission,
		count(*), 
		avg(value), 
		nvl(stddev(value),0),
		avg(logvalue), 
		nvl(stddev(logvalue),0),
		sum(severe), 
		(case when sum(severe)=0 then -999 else avg(case when severe=1 then value else null end) end), 
		(case when sum(severe)=0 then -999 else nvl(stddev(case when severe=1 then value else null end),0) end),
		(case when sum(severe)=0 then -999 else avg(case when severe=1 then logvalue else null end) end), 
		(case when sum(severe)=0 then -999 else nvl(stddev(case when severe=1 then logvalue else null end),0) end),
		sum(1-severe), 
		(case when sum(1-severe)=0 then -999 else avg(case when severe=0 then value else null end) end), 
		(case when sum(1-severe)=0 then -999 else nvl(stddev(case when severe=0 then value else null end),0) end),
		(case when sum(1-severe)=0 then -999 else avg(case when severe=0 then logvalue else null end) end), 
		(case when sum(1-severe)=0 then -999 else nvl(stddev(case when severe=0 then logvalue else null end),0) end)
	from fource_observations
	where concept_type='LAB-LOINC' and days_since_admission>=0
	group by cohort, concept_code, days_since_admission;
commit;
--------------------------------------------------------------------------------
-- LocalDiagProcMed
--------------------------------------------------------------------------------
--drop table fource_LocalDiagProcMed;
create table fource_LocalDiagProcMed (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	concept_type varchar(50) not null,
	concept_code varchar(50) not null,
	pts_all_before_adm int,	-- an observation occurred from day @lookback_days to -15 relative to the admission date
	pts_all_since_adm int, -- an observation occurred on day >=0
	pts_all_dayN14toN1 int, -- an observation occurred from day -14 to -1
	pts_all_day0to29 int, -- an observation occurred from day 0 to 29
	pts_all_day30to89 int, -- an observation occurred from day 30 to 89
	pts_all_day30plus int, -- an observation occurred on day >=30
	pts_all_day90plus int, -- an observation occurred on day >=90
	pts_all_1st_day0to29 int, -- the first observation is day 0 to 29 (no observations from day @lookback_days to -1)
	pts_all_1st_day30plus int, -- the first observation is day >=30 (no observations from day @lookback_days to 29)
	pts_all_1st_day90plus int, -- the first observation is day >=90 (no observations from day @lookback_days to 89)
	pts_ever_severe_before_adm int,
	pts_ever_severe_since_adm int,
	pts_ever_severe_dayN14toN1 int,
	pts_ever_severe_day0to29 int,
	pts_ever_severe_day30to89 int,
	pts_ever_severe_day30plus int,
	pts_ever_severe_day90plus int,
	pts_ever_severe_1st_day0to29 int,
	pts_ever_severe_1st_day30plus int,
	pts_ever_severe_1st_day90plus int
);
alter table fource_LocalDiagProcMed add primary key (cohort, concept_type, concept_code, siteid);
insert into fource_LocalDiagProcMed
	select  (select siteid from fource_config where rownum = 1) siteid, 
            cohort, concept_type, concept_code,
			sum(before_adm),
			sum(since_adm),
			sum(dayN14toN1),
			sum(day0to29),
			sum(day30to89),
			sum(day30plus),
			sum(day90plus),
			sum(case when first_day between 0 and 29 then 1 else 0 end),
			sum(case when first_day >= 30 then 1 else 0 end),
			sum(case when first_day >= 90 then 1 else 0 end),
			sum(severe*before_adm),
			sum(severe*since_adm),
			sum(severe*dayN14toN1),
			sum(severe*day0to29),
			sum(severe*day30to89),
			sum(severe*day30plus),
			sum(severe*day90plus),
			sum(severe*(case when first_day between 0 and 29 then 1 else 0 end)),
			sum(severe*(case when first_day >= 30 then 1 else 0 end)),
			sum(severe*(case when first_day >= 90 then 1 else 0 end))
	from (
		select cohort, patient_num, severe, concept_type,
			(case when concept_type in ('DIAG-ICD9','DIAG-ICD10') then substr(concept_code,1,3) else concept_code end) concept_code,
			--max(case when days_since_admission between @lookback_days and -15 then 1 else 0 end) before_adm,
			max(case when days_since_admission between -365 and -15 then 1 else 0 end) before_adm,
			max(case when days_since_admission between -14 and -1 then 1 else 0 end) dayN14toN1,
			max(case when days_since_admission >= 0 then 1 else 0 end) since_adm,
			max(case when days_since_admission between 0 and 29 then 1 else 0 end) day0to29,
			max(case when days_since_admission between 30 and 89 then 1 else 0 end) day30to89,
			max(case when days_since_admission >= 30 then 1 else 0 end) day30plus,
			max(case when days_since_admission >= 90 then 1 else 0 end) day90plus,
			min(case when days_since_admission >= 0 then days_since_admission else null end) first_day_since_adm,
			min(days_since_admission) first_day
		from fource_observations
		where concept_type in ('DIAG-ICD9','DIAG-ICD10','MED-CLASS','PROC-GROUP','COVID-TEST','SEVERE-LAB','SEVERE-DIAG')
		group by cohort, patient_num, severe, concept_type, 
			(case when concept_type in ('DIAG-ICD9','DIAG-ICD10') then substr(concept_code,1,3) else concept_code end)
	) t
	group by cohort, concept_type, concept_code;
commit;
--------------------------------------------------------------------------------
-- LocalRaceByLocalCode
--------------------------------------------------------------------------------
--drop table fource_LocalRaceByLocalCode;
create table fource_LocalRaceByLocalCode (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	race_local_code varchar(500) not null,
	race_4ce varchar(100) not null,
	pts_all int not null,
	pts_ever_severe int not null
);
alter table fource_LocalRaceByLocalCode add primary key (cohort, race_local_code, siteid);
insert into fource_LocalRaceByLocalCode
	select (select siteid from fource_config where rownum = 1), r.cohort, r.race_local_code, r.race_4ce, count(*), sum(p.severe)
	from fource_LocalPatientRace r
		inner join fource_cohort_patients p
			on r.cohort=p.cohort and r.patient_num=p.patient_num
	group by r.cohort, r.race_local_code, r.race_4ce;
commit;
--------------------------------------------------------------------------------
-- LocalRaceBy4CECode
--------------------------------------------------------------------------------
create table fource_LocalRaceBy4CECode (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	race_4ce varchar(100) not null,
	pts_all int not null,
	pts_ever_severe int not null
);
 alter table fource_LocalRaceBy4CECode add primary key (cohort, race_4ce, siteid);
 insert into fource_LocalRaceBy4CECode
	select (select siteid from fource_config where rownum = 1), r.cohort, r.race_4ce, count(*), sum(p.severe)
	from fource_LocalPatientRace r
		inner join fource_cohort_patients p
			on r.cohort=p.cohort and r.patient_num=p.patient_num
	group by r.cohort, r.race_4ce;
commit;


--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--###
--### Assemble data for Phase 1 shared AGGREGATE COUNT tables.
--### These are the shared versions which may include obfuscation.
--###
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################



--------------------------------------------------------------------------------
-- Cohorts
-------------------------------------------------------------------------------
create table fource_Cohorts (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	source_data_updated_date date not null,
	earliest_adm_date date not null,
	latest_adm_date date not null
);
alter table fource_Cohorts add primary key (cohort, siteid);
--truncate table fource_Cohorts;

insert into fource_Cohorts
	select (select siteid from fource_config where rownum = 1), cohort, source_data_updated_date, earliest_adm_date, latest_adm_date 
	from fource_cohort_config
	where include_in_phase1=1;
commit;
--------------------------------------------------------------------------------
-- DailyCounts
--------------------------------------------------------------------------------
--drop table fource_DailyCounts;
create table fource_DailyCounts (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	calendar_date date not null,
	cumulative_pts_all int not null,
	cumulative_pts_icu int not null,
	cumulative_pts_dead int not null,
	cumulative_pts_severe int not null,
	cumulative_pts_severe_icu int not null,
	cumulative_pts_severe_dead int not null,
	pts_in_hosp_on_this_date int not null,
	pts_in_icu_on_this_date int not null,
	pts_severe_in_hosp_on_date int not null,
	pts_severe_in_icu_on_date int not null
);
alter table fource_DailyCounts add primary key (cohort, calendar_date, siteid);
insert into fource_DailyCounts 
	select *
	from fource_LocalDailyCounts
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);
COMMIT;
--------------------------------------------------------------------------------
-- ClinicalCourse
--------------------------------------------------------------------------------
--drop table fource_CLinicalCourse;
create table fource_ClinicalCourse (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	days_since_admission int not null,
	pts_all_in_hosp int not null,
	pts_all_in_icu int not null,
	pts_all_dead int not null,
	pts_severe_by_this_day int not null,
	pts_ever_severe_in_hosp int not null,
	pts_ever_severe_in_icu int not null,
	pts_ever_severe_dead int not null
);
alter table fource_ClinicalCourse add primary key (cohort, days_since_admission);
insert into fource_ClinicalCourse 
	select * 
	from fource_LocalClinicalCourse
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);
commit;
--------------------------------------------------------------------------------
-- AgeSex
--------------------------------------------------------------------------------
--drop table fource_AgeSex;
create table fource_AgeSex (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	age_group varchar(20) not null,
	mean_age numeric(18,10) not null,
	sex varchar(10) not null,
	pts_all int not null,
	pts_ever_severe int not null
);
alter table fource_AgeSex add primary key (cohort, age_group, sex, siteid);
insert into fource_AgeSex 
	select * 
	from fource_LocalAgeSex
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);
commit;
--------------------------------------------------------------------------------
-- Labs
--------------------------------------------------------------------------------
--drop table fource_Labs;
create table fource_Labs (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	loinc varchar(20) not null,
	days_since_admission int not null,
	pts_all int,
	mean_value_all numeric(18,5),
	stddev_value_all numeric(18,5),
	mean_log_value_all numeric(18,10),
	stddev_log_value_all numeric(18,10),
	pts_ever_severe int,
	mean_value_ever_severe numeric(18,5),
	stddev_value_ever_severe numeric(18,5),
	mean_log_value_ever_severe numeric(18,10),
	stddev_log_value_ever_severe numeric(18,10),
	pts_never_severe int,
	mean_value_never_severe numeric(18,5),
	stddev_value_never_severe numeric(18,5),
	mean_log_value_never_severe numeric(18,10),
	stddev_log_value_never_severe numeric(18,10)
);
alter table fource_Labs add primary key (cohort, loinc, days_since_admission, siteid);
insert into fource_Labs 
	select * 
	from fource_LocalLabs
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);
commit;
--------------------------------------------------------------------------------
-- DiagProcMed
--------------------------------------------------------------------------------
--drop table fource_DiagProcMed;
create table fource_DiagProcMed (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	concept_type varchar(50) not null,
	concept_code varchar(50) not null,
	pts_all_before_adm int,
	pts_all_since_adm int,
	pts_all_dayN14toN1 int,
	pts_all_day0to29 int,
	pts_all_day30to89 int,
	pts_all_day30plus int,
	pts_all_day90plus int,
	pts_all_1st_day0to29 int,
	pts_all_1st_day30plus int,
	pts_all_1st_day90plus int,
	pts_ever_severe_before_adm int,
	pts_ever_severe_since_adm int,
	pts_ever_severe_dayN14toN1 int,
	pts_ever_severe_day0to29 int,
	pts_ever_severe_day30to89 int,
	pts_ever_severe_day30plus int,
	pts_ever_severe_day90plus int,
	pts_ever_severe_1st_day0to29 int,
	pts_ever_severe_1st_day30plus int,
	pts_ever_severe_1st_day90plus int
);
alter table fource_DiagProcMed add primary key (cohort, concept_type, concept_code, siteid);
insert into fource_DiagProcMed 
	select * 
	from fource_LocalDiagProcMed
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);
commit;
--------------------------------------------------------------------------------
-- RaceByLocalCode
--------------------------------------------------------------------------------
create table fource_RaceByLocalCode (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	race_local_code varchar(500) not null,
	race_4ce varchar(100) not null,
	pts_all int not null,
	pts_ever_severe int not null
);
alter table fource_RaceByLocalCode add primary key (cohort, race_local_code, siteid);
insert into fource_RaceByLocalCode 
	select * 
	from fource_LocalRaceByLocalCode
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);
commit;
--------------------------------------------------------------------------------
-- RaceBy4CECode
--------------------------------------------------------------------------------
--drop table fource_RaceBy4CECode;
create table fource_RaceBy4CECode (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	race_4ce varchar(100) not null,
	pts_all int not null,
	pts_ever_severe int not null
);
alter table fource_RaceBy4CECode add primary key (cohort, race_4ce, siteid);
insert into fource_RaceBy4CECode 
	select * 
	from fource_LocalRaceBy4CECode
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);

--------------------------------------------------------------------------------
-- LabCodes
--------------------------------------------------------------------------------
create table fource_LabCodes (
	siteid varchar(50) not null,
	fource_loinc varchar(20) not null, 
	fource_lab_units varchar(20) not null, 
	fource_lab_name varchar(100) not null,
	scale_factor float not null, 
	local_lab_code varchar(50) not null, 
	local_lab_units varchar(20) not null, 
	local_lab_name varchar(500) not null,
	notes varchar(1000)
);
alter table fource_LabCodes add primary key (fource_loinc, local_lab_code, local_lab_units, siteid);
insert into fource_LabCodes
	select (select siteid from fource_config where rownum = 1), fource_loinc, fource_lab_units, fource_lab_name, scale_factor, replace(local_lab_code,',',';'), replace(local_lab_units,',',';'), replace(local_lab_name,',',';'), replace(notes,',',';')
	from fource_lab_map_report;



--******************************************************************************
--******************************************************************************
--*** Obfuscate the shared Phase 1 files as needed (optional)
--******************************************************************************
--******************************************************************************


--------------------------------------------------------------------------------
-- Blur counts by adding a small random number.
--------------------------------------------------------------------------------
    update fource_DailyCounts
        set cumulative_pts_all = (round(cumulative_pts_all/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			cumulative_pts_icu = (round(cumulative_pts_icu/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			cumulative_pts_dead = (round(cumulative_pts_dead/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			cumulative_pts_severe = (round(cumulative_pts_severe/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			cumulative_pts_severe_icu = (round(cumulative_pts_severe_icu/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			cumulative_pts_severe_dead = (round(cumulative_pts_severe_dead/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_in_hosp_on_this_date = (round(pts_in_hosp_on_this_date/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_in_icu_on_this_date = (round(pts_in_icu_on_this_date/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_severe_in_hosp_on_date = (round(pts_severe_in_hosp_on_date/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_severe_in_icu_on_date = (round(pts_severe_in_icu_on_date/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) 
	where (select obfuscation_blur from fource_config where rownum = 1) > 0;
	update fource_ClinicalCourse
		set pts_all_in_hosp = (round(pts_all_in_hosp/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_all_in_icu = (round(pts_all_in_icu/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_all_dead = (round(pts_all_dead/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_severe_by_this_day = (round(pts_severe_by_this_day/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_in_hosp = (round(pts_ever_severe_in_hosp/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_in_icu = (round(pts_ever_severe_in_icu/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_dead = (round(pts_ever_severe_dead/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1)))
	where (select obfuscation_blur from fource_config where rownum = 1) > 0;
	update fource_AgeSex
		set pts_all = (round(pts_all/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe = (round(pts_ever_severe/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1)))
	where (select obfuscation_blur from fource_config where rownum = 1) > 0;
	update fource_Labs
		set pts_all = (round(pts_all/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe = (round(pts_ever_severe/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_never_severe = (round(pts_never_severe/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1)))
    where (select obfuscation_blur from fource_config where rownum = 1) > 0;
	update fource_DiagProcMed
		set pts_all_before_adm = (round(pts_all_before_adm/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_all_since_adm = (round(pts_all_since_adm/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_all_dayN14toN1 = (round(pts_all_dayN14toN1/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_all_day0to29 = (round(pts_all_day0to29/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_all_day30to89 = (round(pts_all_day30to89/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_all_day30plus = (round(pts_all_day30plus/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_all_day90plus = (round(pts_all_day90plus/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_all_1st_day0to29 = (round(pts_all_1st_day0to29/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_all_1st_day30plus = (round(pts_all_1st_day30plus/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_all_1st_day90plus = (round(pts_all_1st_day90plus/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_before_adm = (round(pts_ever_severe_before_adm/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_since_adm = (round(pts_ever_severe_since_adm/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_dayN14toN1 = (round(pts_ever_severe_dayN14toN1/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_day0to29 = (round(pts_ever_severe_day0to29/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_day30to89 = (round(pts_ever_severe_day30to89/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_day30plus = (round(pts_ever_severe_day30plus/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_day90plus = (round(pts_ever_severe_day90plus/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_1st_day0to29 = (round(pts_ever_severe_1st_day0to29/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_1st_day30plus = (round(pts_ever_severe_1st_day30plus/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe_1st_day90plus = (round(pts_ever_severe_1st_day90plus/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1)))
    where (select obfuscation_blur from fource_config where rownum = 1) > 0;
	update fource_RaceByLocalCode
		set pts_all = (round(pts_all/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe = (round(pts_ever_severe/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1)))
	where (select obfuscation_blur from fource_config where rownum = 1) > 0;
	update fource_RaceBy4CECode
		set pts_all = (round(pts_all/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1))) ,
			pts_ever_severe = (round(pts_ever_severe/5.0,0)*5)+greatest(-1*(select obfuscation_blur from fource_config where rownum = 1),least(round(dbms_random.normal*2.8,0),(select obfuscation_blur from fource_config where rownum = 1)))
    where (select obfuscation_blur from fource_config where rownum = 1) > 0;


--------------------------------------------------------------------------------
-- Mask small counts with "-99".
--------------------------------------------------------------------------------
    update fource_DailyCounts
		set cumulative_pts_all = (case when cumulative_pts_all<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else cumulative_pts_all end),
			cumulative_pts_icu = (case when cumulative_pts_icu=-999 then -999 when cumulative_pts_icu<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else cumulative_pts_icu end),
			cumulative_pts_dead = (case when cumulative_pts_dead=-999 then -999 when cumulative_pts_dead<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else cumulative_pts_dead end),
			cumulative_pts_severe = (case when cumulative_pts_severe<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else cumulative_pts_severe end),
			cumulative_pts_severe_icu = (case when cumulative_pts_severe_icu=-999 then -999 when cumulative_pts_severe_icu<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else cumulative_pts_severe_icu end),
			cumulative_pts_severe_dead = (case when cumulative_pts_severe_dead=-999 then -999 when cumulative_pts_severe_dead<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else cumulative_pts_severe_dead end),
			pts_in_hosp_on_this_date = (case when pts_in_hosp_on_this_date<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_in_hosp_on_this_date end),
			pts_in_icu_on_this_date = (case when pts_in_icu_on_this_date=-999 then -999 when pts_in_icu_on_this_date<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_in_icu_on_this_date end),
			pts_severe_in_hosp_on_date = (case when pts_severe_in_hosp_on_date<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_severe_in_hosp_on_date end),
			pts_severe_in_icu_on_date = (case when pts_severe_in_icu_on_date=-999 then -999 when pts_severe_in_icu_on_date<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_severe_in_icu_on_date end)
	where (select obfuscation_small_count_mask from fource_config where rownum=1)  > 0;
    
	update fource_ClinicalCourse
		set pts_all_in_hosp = (case when pts_all_in_hosp<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_in_hosp end),
			pts_all_in_icu = (case when pts_all_in_icu=-999 then -999 when pts_all_in_icu<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_in_icu end),
			pts_all_dead = (case when pts_all_dead=-999 then -999 when pts_all_dead<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_dead end),
			pts_severe_by_this_day = (case when pts_severe_by_this_day<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_severe_by_this_day end),
			pts_ever_severe_in_hosp = (case when pts_ever_severe_in_hosp<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_in_hosp end),
			pts_ever_severe_in_icu = (case when pts_ever_severe_in_icu=-999 then -999 when pts_ever_severe_in_icu<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_in_icu end),
			pts_ever_severe_dead = (case when pts_ever_severe_dead=-999 then -999 when pts_ever_severe_dead<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_dead end)
	where (select obfuscation_small_count_mask from fource_config where rownum=1)  > 0;

	update fource_AgeSex
		set pts_all = (case when pts_all<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all end),
			pts_ever_severe = (case when pts_ever_severe<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe end)
	where (select obfuscation_small_count_mask from fource_config where rownum=1)  > 0;

	update fource_Labs
		set pts_all=-99, mean_value_all=-99, stddev_value_all=-99, mean_log_value_all=-99, stddev_log_value_all=-99
		where pts_all<(select obfuscation_small_count_mask from fource_config where rownum=1)
	where (select obfuscation_small_count_mask from fource_config where rownum=1)  > 0;
    
	update fource_Labs -- Need to mask both ever_severe and never_severe if either of them are below the small count threshold, since all=ever+never
		set pts_ever_severe=-99, mean_value_ever_severe=-99, stddev_value_ever_severe=-99, mean_log_value_ever_severe=-99, stddev_log_value_ever_severe=-99,
			pts_never_severe=-99, mean_value_never_severe=-99, stddev_value_never_severe=-99, mean_log_value_never_severe=-99, stddev_log_value_never_severe=-99
		where (pts_ever_severe<(select obfuscation_small_count_mask from fource_config where rownum=1)) or (pts_never_severe<(select obfuscation_small_count_mask from fource_config where rownum=1))
	where (select obfuscation_small_count_mask from fource_config where rownum=1)  > 0;

	update fource_DiagProcMed
		set pts_all_before_adm = (case when pts_all_before_adm<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_before_adm end),
			pts_all_since_adm = (case when pts_all_since_adm<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_since_adm end),
			pts_all_dayN14toN1 = (case when pts_all_dayN14toN1<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_dayN14toN1 end),
			pts_all_day0to29 = (case when pts_all_day0to29<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_day0to29 end),
			pts_all_day30to89 = (case when pts_all_day30to89<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_day30to89 end),
			pts_all_day30plus = (case when pts_all_day30plus<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_day30plus end),
			pts_all_day90plus = (case when pts_all_day90plus<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_day90plus end),
			pts_all_1st_day0to29 = (case when pts_all_1st_day0to29<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_1st_day0to29 end),
			pts_all_1st_day30plus = (case when pts_all_1st_day30plus<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_1st_day30plus end),
			pts_all_1st_day90plus = (case when pts_all_1st_day90plus<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all_1st_day90plus end),
			pts_ever_severe_before_adm = (case when pts_ever_severe_before_adm<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_before_adm end),
			pts_ever_severe_since_adm = (case when pts_ever_severe_since_adm<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_since_adm end),
			pts_ever_severe_dayN14toN1 = (case when pts_ever_severe_dayN14toN1<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_dayN14toN1 end),
			pts_ever_severe_day0to29 = (case when pts_ever_severe_day0to29<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_day0to29 end),
			pts_ever_severe_day30to89 = (case when pts_ever_severe_day30to89<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_day30to89 end),
			pts_ever_severe_day30plus = (case when pts_ever_severe_day30plus<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_day30plus end),
			pts_ever_severe_day90plus = (case when pts_ever_severe_day90plus<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_day90plus end),
			pts_ever_severe_1st_day0to29 = (case when pts_ever_severe_1st_day0to29<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_1st_day0to29 end),
			pts_ever_severe_1st_day30plus = (case when pts_ever_severe_1st_day30plus<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_1st_day30plus end),
			pts_ever_severe_1st_day90plus = (case when pts_ever_severe_1st_day90plus<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe_1st_day90plus end)
	where (select obfuscation_small_count_mask from fource_config where rownum=1)  > 0;
    
	update fource_RaceByLocalCode
		set pts_all = (case when pts_all<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all end),
			pts_ever_severe = (case when pts_ever_severe<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe end)
	where (select obfuscation_small_count_mask from fource_config where rownum=1)  > 0;
    
	update fource_RaceBy4CECode
		set pts_all = (case when pts_all<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_all end),
			pts_ever_severe = (case when pts_ever_severe<(select obfuscation_small_count_mask from fource_config where rownum=1) then -99 else pts_ever_severe end)
	where (select obfuscation_small_count_mask from fource_config where rownum=1)  > 0;


--------------------------------------------------------------------------------
-- To protect obfuscated age and sex breakdowns, set combinations and 
--   the total count to -999.
--------------------------------------------------------------------------------
	update fource_AgeSex
		set pts_all = -999, pts_ever_severe = -999, mean_age = -999
		where (age_group<>'all') and (sex<>'all') and (select obfuscation_agesex from fource_config where rownum = 1) = 1;


--------------------------------------------------------------------------------
-- Delete small counts.
--------------------------------------------------------------------------------
	delete from fource_DailyCounts where cumulative_pts_all<(select obfuscation_small_count_delete from fource_config where rownum = 1) 
        and (select obfuscation_small_count_delete from fource_config where rownum = 1) > 0;
	delete from fource_ClinicalCourse 
        where pts_all_in_hosp<(select obfuscation_small_count_delete from fource_config where rownum = 1) and pts_all_dead<(select obfuscation_small_count_delete from fource_config where rownum = 1) 
        and pts_severe_by_this_day<(select obfuscation_small_count_delete from fource_config where rownum = 1)
        and (select obfuscation_small_count_delete from fource_config where rownum = 1) > 0;
	delete from fource_Labs where pts_all<(select obfuscation_small_count_delete from fource_config where rownum = 1)
        and (select obfuscation_small_count_delete from fource_config where rownum = 1) > 0;
	delete from fource_DiagProcMed 
		where pts_all_before_adm<(select obfuscation_small_count_delete from fource_config where rownum = 1) 
			and pts_all_since_adm<(select obfuscation_small_count_delete from fource_config where rownum = 1) 
			and pts_all_dayN14toN1<(select obfuscation_small_count_delete from fource_config where rownum = 1)
            and (select obfuscation_small_count_delete from fource_config where rownum = 1) > 0;
	--Do not delete small count rows from Age, Sex, and Race tables.
	--We want to know the rows in the tables, even if the counts are masked.
	--delete from fource_AgeSex where pts_all<(select obfuscation_small_count_delete from fource_config where rownum = 1)
	--delete from fource_RaceByLocalCode where pts_all<@obfuscation_small_count_delete
	--delete from fource_RaceBy4CECode where pts_all<@obfuscation_small_count_delete

--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--###
--### Finish up
--###
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################



--------------------------------------------------------------------------------
-- Delete cohorts that should not be included in Phase2 patient level files
--------------------------------------------------------------------------------
--Phase 2 patient level tables
delete from fource_LocalPatientClinicalCourse where cohort in (select cohort from fource_cohort_config where include_in_phase2=0);
delete from fource_LocalPatientSummary where cohort in (select cohort from fource_cohort_config where include_in_phase2=0);
delete from fource_LocalPatientObservations where cohort in (select cohort from fource_cohort_config where include_in_phase2=0);
delete from fource_LocalPatientRace where cohort in (select cohort from fource_cohort_config where include_in_phase2=0);

--------------------------------------------------------------------------------
-- Remove rows where all values are zeros to reduce the size of the files
--------------------------------------------------------------------------------
delete from fource_LocalPatientClinicalCourse where in_hospital=0 and severe=0 and in_icu=0 and dead=0;

--------------------------------------------------------------------------------
-- Replace the patient_num with a random study_num integer Phase2 tables
-- if replace_patient_num is set to 0 this code won't do anything so you can comment out 
--------------------------------------------------------------------------------
create table fource_LocalPatientMapping (
	siteid varchar(50) not null,
	patient_num int not null,
	study_num int not null
);
alter table fource_LocalPatientMapping add primary key (patient_num, study_num, siteid);

--Create new patient_nums and a mapping table
insert into fource_LocalPatientMapping (siteid, patient_num, study_num)
		select (select siteid from fource_config where   rownum = 1) siteid, 
        patient_num, rownum 
		from (
			select distinct patient_num
			from fource_LocalPatientSummary
		) t
        where (select replace_patient_num from fource_config where  rownum = 1) = 1;


ALTER TABLE fource_LocalPatientClinicalCourse ADD patient_num_orig int;
update fource_LocalPatientClinicalCourse set patient_num_orig = patient_num;               
merge into fource_LocalPatientClinicalCourse t 
using (select patient_num, study_num 
        from fource_LocalPatientMapping where (select replace_patient_num from fource_config where rownum = 1) = 1) m
on (t.patient_num_orig = m.patient_num)
when matched then
update set patient_num = m.study_num;
ALTER TABLE fource_LocalPatientClinicalCourse drop column patient_num_orig;
commit;

ALTER TABLE fource_LocalPatientSummary ADD patient_num_orig int;
update fource_LocalPatientSummary set patient_num_orig = patient_num;               
merge into fource_LocalPatientSummary t 
using (select patient_num, study_num 
        from fource_LocalPatientMapping where (select replace_patient_num from fource_config where rownum = 1) = 1) m
on (t.patient_num_orig = m.patient_num)
when matched then
update set patient_num = m.study_num;
ALTER TABLE fource_LocalPatientSummary drop column patient_num_orig;
commit;

ALTER TABLE fource_LocalPatientObservations ADD patient_num_orig int;
update fource_LocalPatientObservations set patient_num_orig = patient_num;               
merge into fource_LocalPatientObservations t 
using (select patient_num, study_num 
        from fource_LocalPatientMapping where (select replace_patient_num from fource_config where rownum = 1) = 1) m
on (t.patient_num_orig = m.patient_num)
when matched then
update set patient_num = m.study_num;
ALTER TABLE fource_LocalPatientObservations drop column patient_num_orig;
commit;

ALTER TABLE fource_LocalPatientRace ADD patient_num_orig int;
update fource_LocalPatientRace set patient_num_orig = patient_num;               
merge into fource_LocalPatientRace t 
using (select patient_num, study_num 
        from fource_LocalPatientMapping where (select replace_patient_num from fource_config where rownum = 1) = 1) m
on (t.patient_num_orig = m.patient_num)
when matched then
update set patient_num = m.study_num;
ALTER TABLE fource_LocalPatientRace drop column patient_num_orig;
commit;

-- Else map existing patient_num to itself
insert into fource_LocalPatientMapping (siteid, patient_num, study_num)
		select distinct  (select siteid from fource_config where   rownum = 1) siteid, patient_num, patient_num
		from fource_LocalPatientSummary
    where (select replace_patient_num from fource_config where   rownum = 1) = 0;
commit;

/* NOt necessaryalready done. Oracle did not like the '' in the above statements so put the site id 
as tables were being buily 
--------------------------------------------------------------------------------
-- Set the siteid to a unique value for your institution.
-- * Make sure you are not using another institution's siteid.
-- * The siteid must be no more than 20 letters or numbers.
-- * It must start with a letter.
-- * It cannot have any blank spaces or special characters.
--------------------------------------------------------------------------------
--Phase 2 patient level tables
update fource_LocalPatientClinicalCourse set siteid = (select siteid from fource_config)
update fource_LocalPatientSummary set siteid = (select siteid from fource_config)
update fource_LocalPatientObservations set siteid = (select siteid from fource_config)
update fource_LocalPatientRace set siteid = (select siteid from fource_config)
update fource_LocalPatientMapping set siteid = (select siteid from fource_config)
--Phase 2 aggregate count tables
update fource_LocalCohorts set siteid = (select siteid from fource_config)
update fource_LocalDailyCounts set siteid = (select siteid from fource_config)
update fource_LocalClinicalCourse set siteid = (select siteid from fource_config)
update fource_LocalAgeSex set siteid = (select siteid from fource_config)
update fource_LocalLabs set siteid = (select siteid from fource_config)
update fource_LocalDiagProcMed set siteid = (select siteid from fource_config)
update fource_LocalRaceByLocalCode set siteid = (select siteid from fource_config)
update fource_LocalRaceBy4CECode set siteid = (select siteid from fource_config)
--Phase 1 aggregate count tables
update fource_Cohorts set siteid = (select siteid from fource_config)
update fource_DailyCounts set siteid = (select siteid from fource_config)
update fource_ClinicalCourse set siteid = (select siteid from fource_config)
update fource_AgeSex set siteid = (select siteid from fource_config)
update fource_Labs set siteid = (select siteid from fource_config)
update fource_DiagProcMed set siteid = (select siteid from fource_config)
update fource_RaceByLocalCode set siteid = (select siteid from fource_config)
update fource_RaceBy4CECode set siteid = (select siteid from fource_config)
update fource_LabCodes set siteid = (select siteid from fource_config)
*/


--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--###
--### Output results
--###
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################



--******************************************************************************
--******************************************************************************
--*** OPTION #1: View the data as tables.
--*** Make sure everything looks reasonable.
--*** Copy into Excel, convert dates into YYYY-MM-DD format, save in csv format.
--******************************************************************************
--******************************************************************************


	--Phase 1 obfuscated aggregate files
	select * from fource_DailyCounts where (select output_phase1_as_columns from fource_config where rownum=1) = 1 order by cohort, calendar_date ;
	select * from fource_ClinicalCourse where (select output_phase1_as_columns from fource_config where rownum=1) = 1 order by  cohort, days_since_admission;
	select * from fource_AgeSex where (select output_phase1_as_columns from fource_config where rownum=1) = 1 order by  cohort, age_group, sex;
	select * from fource_Labs where (select output_phase1_as_columns from fource_config where rownum=1) = 1 order by  cohort, loinc, days_since_admission;
	select * from fource_DiagProcMed where (select output_phase1_as_columns from fource_config where rownum=1) = 1 order by  cohort, concept_type, concept_code;
	select * from fource_RaceByLocalCode where (select output_phase1_as_columns from fource_config where rownum=1) = 1 order by  cohort, race_local_code;
	select * from fource_RaceBy4CECode where (select output_phase1_as_columns from fource_config where rownum=1) = 1 order by  cohort, race_4ce;
	select * from fource_LabCodes where (select output_phase1_as_columns from fource_config where rownum=1) = 1 order by  fource_loinc, local_lab_code, local_lab_units;

	--Phase 2 non-obfuscated local aggregate files
	select * from fource_LocalDailyCounts where (select output_phase2_as_columns from fource_config where rownum=1) = 1 order by  cohort, calendar_date;
	select * from fource_LocalClinicalCourse where (select output_phase2_as_columns from fource_config where rownum=1) = 1 order by  cohort, days_since_admission;
	select * from fource_LocalAgeSex where (select output_phase2_as_columns from fource_config where rownum=1) = 1 order by  cohort, age_group, sex;
	select * from fource_LocalLabs where (select output_phase2_as_columns from fource_config where rownum=1) = 1 order by  cohort, loinc, days_since_admission;
	select * from fource_LocalDiagProcMed where (select output_phase2_as_columns from fource_config where rownum=1) = 1 order by  cohort, concept_type, concept_code;
	select * from fource_LocalRaceByLocalCode where (select output_phase2_as_columns from fource_config where rownum=1) = 1 order by  cohort, race_local_code;
	select * from fource_LocalRaceBy4CECode where (select output_phase2_as_columns from fource_config where rownum=1) = 1 order by  cohort, race_4ce;
	--Phase 2 patient-level files
	select * from fource_LocalPatientClinicalCourse where (select output_phase2_as_columns from fource_config where rownum=1) = 1 order by  cohort, patient_num, days_since_admission;
	select * from fource_LocalPatientSummary where (select output_phase2_as_columns from fource_config where rownum=1) = 1 order by  cohort, patient_num;
	select * from fource_LocalPatientObservations where (select output_phase2_as_columns from fource_config where rownum=1) = 1 order by  cohort, patient_num, days_since_admission, concept_type, concept_code;
	select * from fource_LocalPatientRace where (select output_phase2_as_columns from fource_config where rownum=1) = 1 order by  cohort, patient_num, race_local_code;
	select * from fource_LocalPatientMapping where (select output_phase2_as_columns from fource_config where rownum=1) = 1 order by  patient_num;




--******************************************************************************
--******************************************************************************
--*** OPTION #2: View the data as csv strings.
--*** Replace @exportFilePath with path to the directory wher you want to dump your files 
--*** and then run the block it will export the csv files using the spool function. 
--*** It may be easier to separate into its own script 
--*** If using SQLDeveloper default params will display only a subset of the file but the entire data set will be spooled
--*** to the appropriate file
--*** If you are in sqldeveloper and run this as a run all it will work 
--*** however if you try to run it as a highlighted block it will not spool properly
--*** Copy and paste to a text file, save it FileName.csv.
--*** Make sure it is not saved as fource_FileName.csv.
--*** Make sure it is not saved as FileName.csv.txt.
--******************************************************************************
--******************************************************************************
set pagesize 0
set echo off
set feedback off
set term off

spool c:\Devtools\NCATS\covid\4cescripts\DailyCounts.csv
select s DailyCountsCSV from ( select 0 z, 'siteid,cohort,calendar_date,cumulative_pts_all,cumulative_pts_icu,cumulative_pts_dead,cumulative_pts_severe,cumulative_pts_severe_icu,cumulative_pts_severe_dead,pts_in_hosp_on_this_date,pts_in_icu_on_this_date,pts_severe_in_hosp_on_date,pts_severe_in_icu_on_date' s from dual union all select row_number() over (order by cohort,calendar_date) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || to_char(calendar_date, 'YYYY-MM-DD') || ',' || cast(cumulative_pts_all as varchar2(2000)) || ',' || cast(cumulative_pts_icu as varchar2(2000)) || ',' || cast(cumulative_pts_dead as varchar2(2000)) || ',' || cast(cumulative_pts_severe as varchar2(2000)) || ',' || cast(cumulative_pts_severe_icu as varchar2(2000)) || ',' || cast(cumulative_pts_severe_dead as varchar2(2000)) || ',' || cast(pts_in_hosp_on_this_date as varchar2(2000)) || ',' || cast(pts_in_icu_on_this_date as varchar2(2000)) || ',' || cast(pts_severe_in_hosp_on_date as varchar2(2000)) || ',' || cast(pts_severe_in_icu_on_date as varchar2(2000)) from fource_DailyCounts union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\ClinicalCourse.csv
select s ClinicalCourseCSV from ( select 0 z, 'siteid,cohort,days_since_admission,pts_all_in_hosp,pts_all_in_icu,pts_all_dead,pts_severe_by_this_day,pts_ever_severe_in_hosp,pts_ever_severe_in_icu,pts_ever_severe_dead' s from dual union all select row_number() over (order by cohort,days_since_admission) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(days_since_admission as varchar2(2000)) || ',' || cast(pts_all_in_hosp as varchar2(2000)) || ',' || cast(pts_all_in_icu as varchar2(2000)) || ',' || cast(pts_all_dead as varchar2(2000)) || ',' || cast(pts_severe_by_this_day as varchar2(2000)) || ',' || cast(pts_ever_severe_in_hosp as varchar2(2000)) || ',' || cast(pts_ever_severe_in_icu as varchar2(2000)) || ',' || cast(pts_ever_severe_dead as varchar2(2000)) from fource_ClinicalCourse union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\AgeSex.csv
select s AgeSexCSV from ( select 0 z, 'siteid,cohort,age_group,mean_age,sex,pts_all,pts_ever_severe' s from dual union all select row_number() over (order by cohort,age_group,sex) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(age_group as varchar2(2000)) || ',' || cast(mean_age as varchar2(2000)) || ',' || cast(sex as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) from fource_AgeSex union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\Labs.csv
select s LabsCSV from ( select 0 z, 'siteid,cohort,loinc,days_since_admission,pts_all,mean_value_all,stddev_value_all,mean_log_value_all,stddev_log_value_all,pts_ever_severe,mean_value_ever_severe,stddev_value_ever_severe,mean_log_value_ever_severe,stddev_log_value_ever_severe,pts_never_severe,mean_value_never_severe,stddev_value_never_severe,mean_log_value_never_severe,stddev_log_value_never_severe' s from dual union all select row_number() over (order by cohort,loinc,days_since_admission) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(loinc as varchar2(2000)) || ',' || cast(days_since_admission as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(mean_value_all as varchar2(2000)) || ',' || cast(stddev_value_all as varchar2(2000)) || ',' || cast(mean_log_value_all as varchar2(2000)) || ',' || cast(stddev_log_value_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) || ',' || cast(mean_value_ever_severe as varchar2(2000)) || ',' || cast(stddev_value_ever_severe as varchar2(2000)) || ',' || cast(mean_log_value_ever_severe as varchar2(2000)) || ',' || cast(stddev_log_value_ever_severe as varchar2(2000)) || ',' || cast(pts_never_severe as varchar2(2000)) || ',' || cast(mean_value_never_severe as varchar2(2000)) || ',' || cast(stddev_value_never_severe as varchar2(2000)) || ',' || cast(mean_log_value_never_severe as varchar2(2000)) || ',' || cast(stddev_log_value_never_severe as varchar2(2000)) from fource_Labs union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\DiagProcMed.csv
select s DiagProcMedCSV from ( select 0 z, 'siteid,cohort,concept_type,concept_code,pts_all_before_adm,pts_all_since_adm,pts_all_dayN14toN1,pts_all_day0to29,pts_all_day30to89,pts_all_day30plus,pts_all_day90plus,pts_all_1st_day0to29,pts_all_1st_day30plus,pts_all_1st_day90plus,pts_ever_severe_before_adm,pts_ever_severe_since_adm,pts_ever_severe_dayN14toN1,pts_ever_severe_day0to29,pts_ever_severe_day30to89,pts_ever_severe_day30plus,pts_ever_severe_day90plus,pts_ever_severe_1st_day0to29,pts_ever_severe_1st_day30plus,pts_ever_severe_1st_day90plus' s from dual union all select row_number() over (order by cohort,concept_type,concept_code) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(concept_type as varchar2(2000)) || ',' || cast(concept_code as varchar2(2000)) || ',' || cast(pts_all_before_adm as varchar2(2000)) || ',' || cast(pts_all_since_adm as varchar2(2000)) || ',' || cast(pts_all_dayN14toN1 as varchar2(2000)) || ',' || cast(pts_all_day0to29 as varchar2(2000)) || ',' || cast(pts_all_day30to89 as varchar2(2000)) || ',' || cast(pts_all_day30plus as varchar2(2000)) || ',' || cast(pts_all_day90plus as varchar2(2000)) || ',' || cast(pts_all_1st_day0to29 as varchar2(2000)) || ',' || cast(pts_all_1st_day30plus as varchar2(2000)) || ',' || cast(pts_all_1st_day90plus as varchar2(2000)) || ',' || cast(pts_ever_severe_before_adm as varchar2(2000)) || ',' || cast(pts_ever_severe_since_adm as varchar2(2000)) || ',' || cast(pts_ever_severe_dayN14toN1 as varchar2(2000)) || ',' || cast(pts_ever_severe_day0to29 as varchar2(2000)) || ',' || cast(pts_ever_severe_day30to89 as varchar2(2000)) || ',' || cast(pts_ever_severe_day30plus as varchar2(2000)) || ',' || cast(pts_ever_severe_day90plus as varchar2(2000)) || ',' || cast(pts_ever_severe_1st_day0to29 as varchar2(2000)) || ',' || cast(pts_ever_severe_1st_day30plus as varchar2(2000)) || ',' || cast(pts_ever_severe_1st_day90plus as varchar2(2000)) from fource_DiagProcMed union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\RaceByLocalCode.csv
select s RaceByLocalCodeCSV from ( select 0 z, 'siteid,cohort,race_local_code,race_4ce,pts_all,pts_ever_severe' s from dual union all select row_number() over (order by cohort,race_local_code) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(race_local_code as varchar2(2000)) || ',' || cast(race_4ce as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) from fource_RaceByLocalCode union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\RaceBy4CECode.csv
select s RaceBy4CECodeCSV from ( select 0 z, 'siteid,cohort,race_4ce,pts_all,pts_ever_severe' s from dual union all select row_number() over (order by cohort,race_4ce) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(race_4ce as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) from fource_RaceBy4CECode union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LabCodes.csv
select s LabCodesCSV from ( select 0 z, 'siteid,fource_loinc,fource_lab_units,fource_lab_name,scale_factor,local_lab_code,local_lab_units,local_lab_name,notes' s from dual union all select row_number() over (order by fource_loinc,local_lab_code,local_lab_units) z, cast(siteid as varchar2(2000)) || ',' || cast(fource_loinc as varchar2(2000)) || ',' || cast(fource_lab_units as varchar2(2000)) || ',' || cast(fource_lab_name as varchar2(2000)) || ',' || cast(scale_factor as varchar2(2000)) || ',' || cast(local_lab_code as varchar2(2000)) || ',' || cast(local_lab_units as varchar2(2000)) || ',' || cast(local_lab_name as varchar2(2000)) || ',' || cast(notes as varchar2(2000)) from fource_LabCodes union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LocalDailyCounts.csv
select s LocalDailyCountsCSV from ( select 0 z, 'siteid,cohort,calendar_date,cumulative_pts_all,cumulative_pts_icu,cumulative_pts_dead,cumulative_pts_severe,cumulative_pts_severe_icu,cumulative_pts_severe_dead,pts_in_hosp_on_this_date,pts_in_icu_on_this_date,pts_severe_in_hosp_on_date,pts_severe_in_icu_on_date' s from dual union all select row_number() over (order by cohort,calendar_date) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || to_char(calendar_date, 'YYYY-MM-DD') || ',' || cast(cumulative_pts_all as varchar2(2000)) || ',' || cast(cumulative_pts_icu as varchar2(2000)) || ',' || cast(cumulative_pts_dead as varchar2(2000)) || ',' || cast(cumulative_pts_severe as varchar2(2000)) || ',' || cast(cumulative_pts_severe_icu as varchar2(2000)) || ',' || cast(cumulative_pts_severe_dead as varchar2(2000)) || ',' || cast(pts_in_hosp_on_this_date as varchar2(2000)) || ',' || cast(pts_in_icu_on_this_date as varchar2(2000)) || ',' || cast(pts_severe_in_hosp_on_date as varchar2(2000)) || ',' || cast(pts_severe_in_icu_on_date as varchar2(2000)) from fource_LocalDailyCounts union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LocalClinicalCourse.csv
select s LocalClinicalCourseCSV from ( select 0 z, 'siteid,cohort,days_since_admission,pts_all_in_hosp,pts_all_in_icu,pts_all_dead,pts_severe_by_this_day,pts_ever_severe_in_hosp,pts_ever_severe_in_icu,pts_ever_severe_dead' s from dual union all select row_number() over (order by cohort,days_since_admission) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(days_since_admission as varchar2(2000)) || ',' || cast(pts_all_in_hosp as varchar2(2000)) || ',' || cast(pts_all_in_icu as varchar2(2000)) || ',' || cast(pts_all_dead as varchar2(2000)) || ',' || cast(pts_severe_by_this_day as varchar2(2000)) || ',' || cast(pts_ever_severe_in_hosp as varchar2(2000)) || ',' || cast(pts_ever_severe_in_icu as varchar2(2000)) || ',' || cast(pts_ever_severe_dead as varchar2(2000)) from fource_LocalClinicalCourse union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LocalAgeSex.csv
select s LocalAgeSexCSV from ( select 0 z, 'siteid,cohort,age_group,mean_age,sex,pts_all,pts_ever_severe' s from dual union all select row_number() over (order by cohort,age_group,sex) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(age_group as varchar2(2000)) || ',' || cast(mean_age as varchar2(2000)) || ',' || cast(sex as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) from fource_LocalAgeSex union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LocalLabs.csv
select s LocalLabsCSV from ( select 0 z, 'siteid,cohort,loinc,days_since_admission,pts_all,mean_value_all,stddev_value_all,mean_log_value_all,stddev_log_value_all,pts_ever_severe,mean_value_ever_severe,stddev_value_ever_severe,mean_log_value_ever_severe,stddev_log_value_ever_severe,pts_never_severe,mean_value_never_severe,stddev_value_never_severe,mean_log_value_never_severe,stddev_log_value_never_severe' s from dual union all select row_number() over (order by cohort,loinc,days_since_admission) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(loinc as varchar2(2000)) || ',' || cast(days_since_admission as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(mean_value_all as varchar2(2000)) || ',' || cast(stddev_value_all as varchar2(2000)) || ',' || cast(mean_log_value_all as varchar2(2000)) || ',' || cast(stddev_log_value_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) || ',' || cast(mean_value_ever_severe as varchar2(2000)) || ',' || cast(stddev_value_ever_severe as varchar2(2000)) || ',' || cast(mean_log_value_ever_severe as varchar2(2000)) || ',' || cast(stddev_log_value_ever_severe as varchar2(2000)) || ',' || cast(pts_never_severe as varchar2(2000)) || ',' || cast(mean_value_never_severe as varchar2(2000)) || ',' || cast(stddev_value_never_severe as varchar2(2000)) || ',' || cast(mean_log_value_never_severe as varchar2(2000)) || ',' || cast(stddev_log_value_never_severe as varchar2(2000)) from fource_LocalLabs union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LocalDiagProcMed.csv
select s LocalDiagProcMedCSV from ( select 0 z, 'siteid,cohort,concept_type,concept_code,pts_all_before_adm,pts_all_since_adm,pts_all_dayN14toN1,pts_all_day0to29,pts_all_day30to89,pts_all_day30plus,pts_all_day90plus,pts_all_1st_day0to29,pts_all_1st_day30plus,pts_all_1st_day90plus,pts_ever_severe_before_adm,pts_ever_severe_since_adm,pts_ever_severe_dayN14toN1,pts_ever_severe_day0to29,pts_ever_severe_day30to89,pts_ever_severe_day30plus,pts_ever_severe_day90plus,pts_ever_severe_1st_day0to29,pts_ever_severe_1st_day30plus,pts_ever_severe_1st_day90plus' s from dual union all select row_number() over (order by cohort,concept_type,concept_code) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(concept_type as varchar2(2000)) || ',' || cast(concept_code as varchar2(2000)) || ',' || cast(pts_all_before_adm as varchar2(2000)) || ',' || cast(pts_all_since_adm as varchar2(2000)) || ',' || cast(pts_all_dayN14toN1 as varchar2(2000)) || ',' || cast(pts_all_day0to29 as varchar2(2000)) || ',' || cast(pts_all_day30to89 as varchar2(2000)) || ',' || cast(pts_all_day30plus as varchar2(2000)) || ',' || cast(pts_all_day90plus as varchar2(2000)) || ',' || cast(pts_all_1st_day0to29 as varchar2(2000)) || ',' || cast(pts_all_1st_day30plus as varchar2(2000)) || ',' || cast(pts_all_1st_day90plus as varchar2(2000)) || ',' || cast(pts_ever_severe_before_adm as varchar2(2000)) || ',' || cast(pts_ever_severe_since_adm as varchar2(2000)) || ',' || cast(pts_ever_severe_dayN14toN1 as varchar2(2000)) || ',' || cast(pts_ever_severe_day0to29 as varchar2(2000)) || ',' || cast(pts_ever_severe_day30to89 as varchar2(2000)) || ',' || cast(pts_ever_severe_day30plus as varchar2(2000)) || ',' || cast(pts_ever_severe_day90plus as varchar2(2000)) || ',' || cast(pts_ever_severe_1st_day0to29 as varchar2(2000)) || ',' || cast(pts_ever_severe_1st_day30plus as varchar2(2000)) || ',' || cast(pts_ever_severe_1st_day90plus as varchar2(2000)) from fource_LocalDiagProcMed union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LocalRaceByLocalCode.csv
select s LocalRaceByLocalCodeCSV from ( select 0 z, 'siteid,cohort,race_local_code,race_4ce,pts_all,pts_ever_severe' s from dual union all select row_number() over (order by cohort,race_local_code) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(race_local_code as varchar2(2000)) || ',' || cast(race_4ce as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) from fource_LocalRaceByLocalCode union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LocalRaceBy4CECode.csv
select s LocalRaceBy4CECodeCSV from ( select 0 z, 'siteid,cohort,race_4ce,pts_all,pts_ever_severe' s from dual union all select row_number() over (order by cohort,race_4ce) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(race_4ce as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) from fource_LocalRaceBy4CECode union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LocalPatientClinicalCourse.csv
select s LocalPatientClinicalCourseCSV from ( select 0 z, 'siteid,cohort,patient_num,days_since_admission,calendar_date,in_hospital,severe,in_icu,dead' s from dual union all select row_number() over (order by cohort,patient_num,days_since_admission) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(patient_num as varchar2(2000)) || ',' || cast(days_since_admission as varchar2(2000)) || ',' || cast(calendar_date as varchar2(2000)) || ',' || cast(in_hospital as varchar2(2000)) || ',' || cast(severe as varchar2(2000)) || ',' || cast(in_icu as varchar2(2000)) || ',' || cast(dead as varchar2(2000)) from fource_LocalPatientClinicalCourse union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LocalPatientSummary.csv
select s LocalPatientSummaryCSV from ( select 0 z, 'siteid,cohort,patient_num,admission_date,source_data_updated_date,days_since_admission,last_discharge_date,still_in_hospital,severe_date,severe,icu_date,icu,death_date,dead,age_group,age,sex' s from dual union all select row_number() over (order by cohort,patient_num) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(patient_num as varchar2(2000)) || ',' || cast(admission_date as varchar2(2000)) || ',' || to_char(source_data_updated_date, 'YYYY-MM-DD') || ',' || cast(days_since_admission as varchar2(2000)) || ',' || to_char(last_discharge_date, 'YYYY-MM-DD') || ',' || cast(still_in_hospital as varchar2(2000)) || ',' || to_char(severe_date, 'YYYY-MM-DD') || ',' || cast(severe as varchar2(2000)) || ',' || to_char(icu_date, 'YYYY-MM-DD') || ',' || cast(icu as varchar2(2000)) || ',' || to_char(death_date, 'YYYY-MM-DD') || ',' || cast(dead as varchar2(2000)) || ',' || cast(age_group as varchar2(2000)) || ',' || cast(age as varchar2(2000)) || ',' || cast(sex as varchar2(2000)) from fource_LocalPatientSummary union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LocalPatientObservations.csv
select s LocalPatientObservationsCSV from ( select 0 z, 'siteid,cohort,patient_num,days_since_admission,concept_type,concept_code,value' s from dual union all select row_number() over (order by cohort,patient_num,days_since_admission,concept_type,concept_code) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(patient_num as varchar2(2000)) || ',' || cast(days_since_admission as varchar2(2000)) || ',' || cast(concept_type as varchar2(2000)) || ',' || cast(concept_code as varchar2(2000)) || ',' || cast(value as varchar2(2000)) from fource_LocalPatientObservations union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LocalPatientRace.csv
select s LocalPatientRaceCSV from ( select 0 z, 'siteid,cohort,patient_num,race_local_code,race_4ce' s from dual union all select row_number() over (order by cohort,patient_num,race_local_code) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(patient_num as varchar2(2000)) || ',' || cast(race_local_code as varchar2(2000)) || ',' || cast(race_4ce as varchar2(2000)) from fource_LocalPatientRace union all select 9999999 z, '' from dual) t order by z;
spool off


spool c:\Devtools\NCATS\covid\4cescripts\LocalPatientMapping.csv
select s LocalPatientMappingCSV from ( select 0 z, 'siteid,patient_num,study_num' s from dual union all select row_number() over (order by patient_num) z, cast(siteid as varchar2(2000)) || ',' || cast(patient_num as varchar2(2000)) || ',' || cast(study_num as varchar2(2000)) from fource_LocalPatientMapping union all select 9999999 z, '' from dual) t order by z;
spool off

--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--###
--### Cleanup to drop temp tables (optional)
--###
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################

/*

-- Main configuration table
drop table fource_config

-- Code mapping tables
drop table fource_code_map
drop table fource_med_map
drop table fource_proc_map
drop table fource_lab_map
drop table fource_lab_units_facts
drop table fource_lab_map_report
-- Admissions, ICU visits, and deaths
drop table fource_admissions
drop table fource_icu
drop table fource_death
-- COVID tests, cohort definitions and patients
drop table fource_cohort_config
drop table fource_covid_tests
drop table fource_first_covid_tests
drop table fource_date_list
drop table fource_cohort_patients
-- List of patients and observations mapped to 4CE codes
drop table fource_patients
drop table fource_observations
-- Used to create the CSV formatted tables
drop table fource_file_csv

-- Phase 1 obfuscated aggregate files
drop table fource_DailyCounts 
drop table fource_ClinicalCourse 
drop table fource_AgeSex 
drop table fource_Labs 
drop table fource_DiagProcMed 
drop table fource_RaceByLocalCode 
drop table fource_RaceBy4CECode 
drop table fource_LabCodes 
-- Phase 2 non-obfuscated local aggregate files
drop table fource_LocalDailyCounts 
drop table fource_LocalClinicalCourse 
drop table fource_LocalAgeSex 
drop table fource_LocalLabs 
drop table fource_LocalDiagProcMed 
drop table fource_LocalRaceByLocalCode 
drop table fource_LocalRaceBy4CECode 
-- Phase 2 patient-level files
drop table fource_LocalPatientSummary 
drop table fource_LocalPatientClinicalCourse 
drop table fource_LocalPatientObservations 
drop table fource_LocalPatientRace 
drop table fource_LocalPatientMapping 

*/


/** Not necessary for ORACLE as there #temp tables are not supported a block to delete all or some of the tables 
will replace this block
-- Optional: Run the commented code below to generate SQL for previously saved tables, rather than the temp tables.
-- Replace "dbo_fource_" with the prefix you used to save the tables.
-- Copy and paste the SQL strings into a query window and run the queries.
 
select file_index, file_name, replace(file_sql,'fource_','dbo_FourCE_') file_sql
	from fource_file_csv
	order by file_index



--******************************************************************************
--******************************************************************************
--*** OPTION #3: Save the data as tables.
--*** Make sure everything looks reasonable.
--*** Export the tables to csv files.
--******************************************************************************
--******************************************************************************
/*

-- delete the truly temp tables
-- delete the tables that contain the Phase 1.2 and Phase 2.2 data set
--TO DO: Delete this code???
--below is irrelevant in oracle
if exists (select * from fource_config where save_phase1_as_columns=1)
begin
	-- Drop existing tables
	declare @SavePhase1AsTablesSQL nvarchar(max)
	select @SavePhase1AsTablesSQL = ''
		--Phase 1 obfuscated aggregate files
		 || 'if (select object_id(''' || save_phase1_as_prefix || 'DailyCounts'', ''U'') from fource_config) is not null drop table ' || save_phase1_as_prefix || 'DailyCounts;'
		 || 'if (select object_id(''' || save_phase1_as_prefix || 'ClinicalCourse'', ''U'') from fource_config) is not null drop table ' || save_phase1_as_prefix || 'ClinicalCourse;'
		 || 'if (select object_id(''' || save_phase1_as_prefix || 'AgeSex'', ''U'') from fource_config) is not null drop table ' || save_phase1_as_prefix || 'AgeSex;'
		 || 'if (select object_id(''' || save_phase1_as_prefix || 'Labs'', ''U'') from fource_config) is not null drop table ' || save_phase1_as_prefix || 'Labs;'
		 || 'if (select object_id(''' || save_phase1_as_prefix || 'DiagProcMed'', ''U'') from fource_config) is not null  drop table ' || save_phase1_as_prefix || 'DiagProcMed;'
		 || 'if (select object_id(''' || save_phase1_as_prefix || 'RaceByLocalCode'', ''U'') from fource_config) is not null drop table ' || save_phase1_as_prefix || 'RaceByLocalCode;'
		 || 'if (select object_id(''' || save_phase1_as_prefix || 'RaceBy4CECode'', ''U'') from fource_config) is not null drop table ' || save_phase1_as_prefix || 'RaceBy4CECode;'
		 || 'if (select object_id(''' || save_phase1_as_prefix || 'LabCodes'', ''U'') from fource_config) is not null drop table ' || save_phase1_as_prefix || 'LabCodes;'
		from fource_config
	exec sp_executesql @SavePhase1AsTablesSQL
	-- Save new tables
	select @SavePhase1AsTablesSQL = ''
		--Phase 1 obfuscated aggregate files
		 || 'select * into ' || save_phase1_as_prefix || 'DailyCounts from fource_DailyCounts;'
		 || 'select * into ' || save_phase1_as_prefix || 'ClinicalCourse from fource_ClinicalCourse;'
		 || 'select * into ' || save_phase1_as_prefix || 'AgeSex from fource_AgeSex;'
		 || 'select * into ' || save_phase1_as_prefix || 'Labs from fource_Labs;'
		 || 'select * into ' || save_phase1_as_prefix || 'DiagProcMed from fource_DiagProcMed;'
		 || 'select * into ' || save_phase1_as_prefix || 'RaceByLocalCode from fource_RaceByLocalCode;'
		 || 'select * into ' || save_phase1_as_prefix || 'RaceBy4CECode from fource_RaceBy4CECode;'
		 || 'select * into ' || save_phase1_as_prefix || 'LabCodes from fource_LabCodes;'
		 || '; alter table ' || save_phase1_as_prefix || 'DailyCounts add primary key (cohort, calendar_date, siteid);'
		 || '; alter table ' || save_phase1_as_prefix || 'ClinicalCourse add primary key (cohort, days_since_admission, siteid);'
		 || '; alter table ' || save_phase1_as_prefix || 'AgeSex add primary key (cohort, age_group, sex, siteid);'
		 || '; alter table ' || save_phase1_as_prefix || 'Labs add primary key (cohort, loinc, days_since_admission, siteid);'
		 || '; alter table ' || save_phase1_as_prefix || 'DiagProcMed add primary key (cohort, concept_type, concept_code, siteid);'
		 || '; alter table ' || save_phase1_as_prefix || 'RaceByLocalCode add primary key (cohort, race_local_code, siteid);'
		 || '; alter table ' || save_phase1_as_prefix || 'RaceBy4CECode add primary key (cohort, race_4ce, siteid);'
		 || '; alter table ' || save_phase1_as_prefix || 'LabCodes add primary key (fource_loinc, local_lab_code, local_lab_units, siteid);'
		from fource_config
	exec sp_executesql @SavePhase1AsTablesSQL
end


--if exists (select * from fource_config where save_phase2_as_columns=1)
--begin
	-- Drop existing tables
--	declare @SavePhase2AsTablesSQL nvarchar(max)
	select @SavePhase2AsTablesSQL = '';
    select ''
		--Phase 2 non-obfuscated local aggregate files
		 || 'if (select object_id(''' || save_phase2_as_prefix || 'LocalDailyCounts'', ''U'') from fource_config) is not null drop table ' || save_phase2_as_prefix || 'LocalDailyCounts;'
		 || 'if (select object_id(''' || save_phase2_as_prefix || 'LocalClinicalCourse'', ''U'') from fource_config) is not null drop table ' || save_phase2_as_prefix || 'LocalClinicalCourse;'
		 || 'if (select object_id(''' || save_phase2_as_prefix || 'LocalAgeSex'', ''U'') from fource_config) is not null drop table ' || save_phase2_as_prefix || 'LocalAgeSex;'
		 || 'if (select object_id(''' || save_phase2_as_prefix || 'LocalLabs'', ''U'') from fource_config) is not null drop table ' || save_phase2_as_prefix || 'LocalLabs;'
		 || 'if (select object_id(''' || save_phase2_as_prefix || 'LocalDiagProcMed'', ''U'') from fource_config) is not null  drop table ' || save_phase2_as_prefix || 'LocalDiagProcMed;'
		 || 'if (select object_id(''' || save_phase2_as_prefix || 'LocalRaceByLocalCode'', ''U'') from fource_config) is not null drop table ' || save_phase2_as_prefix || 'LocalRaceByLocalCode;'
		 || 'if (select object_id(''' || save_phase2_as_prefix || 'LocalRaceBy4CECode'', ''U'') from fource_config) is not null drop table ' || save_phase2_as_prefix || 'LocalRaceBy4CECode;'
		--Phase 2 patient-level files
		 || 'if (select object_id(''' || save_phase2_as_prefix || 'LocalPatientSummary'', ''U'') from fource_config) is not null drop table ' || save_phase2_as_prefix || 'LocalPatientSummary;'
		 || 'if (select object_id(''' || save_phase2_as_prefix || 'LocalPatientClinicalCourse'', ''U'') from fource_config) is not null drop table ' || save_phase2_as_prefix || 'LocalPatientClinicalCourse;'
		 || 'if (select object_id(''' || save_phase2_as_prefix || 'LocalPatientObservations'', ''U'') from fource_config) is not null drop table ' || save_phase2_as_prefix || 'LocalPatientObservations;'
		 || 'if (select object_id(''' || save_phase2_as_prefix || 'LocalPatientRace'', ''U'') from fource_config) is not null drop table ' || save_phase2_as_prefix || 'LocalPatientRace;'
		 || 'if (select object_id(''' || save_phase2_as_prefix || 'LocalPatientMapping'', ''U'') from fource_config) is not null drop table ' || save_phase2_as_prefix || 'LocalPatientMapping;'
		from fource_config;
	exec sp_executesql @SavePhase2AsTablesSQL
	-- Save new tables
    select save_phase2_as_prefix from fource_config;
    select * into ' || save_phase2_as_prefix || 'LocalDailyCounts from fource_LocalDailyCounts;
    
    --If you want to save the Phase 2 data as tables run this block
    

	select @SavePhase2AsTablesSQL = ''
		--Phase 2 non-obfuscated local aggregate files
		 || 'select * into ' || save_phase2_as_prefix || 'LocalDailyCounts from fource_LocalDailyCounts;'
		 || 'select * into ' || save_phase2_as_prefix || 'LocalClinicalCourse from fource_LocalClinicalCourse;'
		 || 'select * into ' || save_phase2_as_prefix || 'LocalAgeSex from fource_LocalAgeSex;'
		 || 'select * into ' || save_phase2_as_prefix || 'LocalLabs from fource_LocalLabs;'
		 || 'select * into ' || save_phase2_as_prefix || 'LocalDiagProcMed from fource_LocalDiagProcMed;'
		 || 'select * into ' || save_phase2_as_prefix || 'LocalRaceByLocalCode from fource_LocalRaceByLocalCode;'
		 || 'select * into ' || save_phase2_as_prefix || 'LocalRaceBy4CECode from fource_LocalRaceBy4CECode;'
		 || '; alter table ' || save_phase2_as_prefix || 'LocalDailyCounts add primary key (cohort, calendar_date, siteid);'
		 || '; alter table ' || save_phase2_as_prefix || 'LocalClinicalCourse add primary key (cohort, days_since_admission, siteid);'
		 || '; alter table ' || save_phase2_as_prefix || 'LocalAgeSex add primary key (cohort, age_group, sex, siteid);'
		 || '; alter table ' || save_phase2_as_prefix || 'LocalLabs add primary key (cohort, loinc, days_since_admission, siteid);'
		 || '; alter table ' || save_phase2_as_prefix || 'LocalDiagProcMed add primary key (cohort, concept_type, concept_code, siteid);'
		 || '; alter table ' || save_phase2_as_prefix || 'LocalRaceByLocalCode add primary key (cohort, race_local_code, siteid);'
		 || '; alter table ' || save_phase2_as_prefix || 'LocalRaceBy4CECode add primary key (cohort, race_4ce, siteid);'
		--Phase 2 patient-level files
		 || 'select * into ' || save_phase2_as_prefix || 'LocalPatientSummary from fource_LocalPatientSummary;'
		 || 'select * into ' || save_phase2_as_prefix || 'LocalPatientClinicalCourse from fource_LocalPatientClinicalCourse;'
		 || 'select * into ' || save_phase2_as_prefix || 'LocalPatientObservations from fource_LocalPatientObservations;'
		 || 'select * into ' || save_phase2_as_prefix || 'LocalPatientRace from fource_LocalPatientRace;'
		 || 'select * into ' || save_phase2_as_prefix || 'LocalPatientMapping from fource_LocalPatientMapping;'
		 || '; alter table ' || save_phase2_as_prefix || 'LocalPatientClinicalCourse add primary key (cohort, patient_num, days_since_admission, siteid);'
		 || '; alter table ' || save_phase2_as_prefix || 'LocalPatientMapping add primary key (patient_num, study_num, siteid);'
		 || '; alter table ' || save_phase2_as_prefix || 'LocalPatientObservations add primary key (cohort, patient_num, days_since_admission, concept_type, concept_code, siteid);'
		 || '; alter table ' || save_phase2_as_prefix || 'LocalPatientRace add primary key (cohort, patient_num, race_local_code, siteid);'
		 || '; alter table ' || save_phase2_as_prefix || 'LocalPatientSummary add primary key (cohort, patient_num, siteid);'
		from fource_config
	exec sp_executesql @SavePhase2AsTablesSQL
end
*/

