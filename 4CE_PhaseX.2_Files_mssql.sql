--##############################################################################
--##############################################################################
--### 4CE Phase 1.2 and 2.2
--### Date: April 21, 2021
--### Database: Microsoft SQL Server
--### Data Model: i2b2
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################

/*

INTRODUCTION:
This script contains code to generate both 4CE Phase 1.2 and Phase 2.2 files.
By default, it will only generate Phase 1.2 files, which contain obfuscated
aggregate counts and statistics. You need to change the settings in the
#fource_config table so that it generates the Phase 2.2 files. Phase 2.2
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
"dbo.FourCE_" that will be added to the begining of each table name.

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
you use a different schema, then do a search-and-replace to change "dbo." to
your schema. The code also assumes you have a single fact table called
"dbo.observation_fact". If you use multiple fact tables, then search for
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



--------------------------------------------------------------------------------
-- General settings
--------------------------------------------------------------------------------
create table #fource_config (
	siteid varchar(20), -- Up to 20 letters or numbers, must start with letter, no spaces or special characters.
	race_data_available bit, -- 1 if your site collects race/ethnicity data; 0 if your site does not collect this.
	icu_data_available bit, -- 1 if you have data on whether patients were in the ICU
	death_data_available bit, -- 1 if you have data on whether patients have died
	code_prefix_icd9cm varchar(50), -- prefix (scheme) used in front of a ICD9CM diagnosis code; set to '' if not collected or no prefix used
	code_prefix_icd10cm varchar(50), -- prefix (scheme) used in front of a ICD10CM diagnosis code; set to '' if not collected or no prefix used
	source_data_updated_date date, -- the date your source data were last updated (e.g., '3/25/2021'); set to NULL if data go to the day you run this script
	-- Phase 1.2 (obfuscated aggregate data) options
	include_extra_cohorts_phase1 bit, -- 0 by default, 1 to include COVID negative, U07.1, and non-admitted cohorts to Phase 1 files
	obfuscation_blur int, -- Add random number +/-blur to each count (0 = no blur)
	obfuscation_small_count_mask int, -- Replace counts less than mask with -99 (0 = no small count masking)
	obfuscation_small_count_delete bit, -- Delete rows where all values are small counts (0 = no, 1 = yes)
	obfuscation_agesex bit, -- Replace combination of age-sex and total counts with -999 (0 = no, 1 = yes)
	output_phase1_as_columns bit, -- Return the data in tables with separate columns per field
	output_phase1_as_csv bit, -- Return the data in tables with a single column containing comma separated values
	save_phase1_as_columns bit, -- Save the data as tables with separate columns per field
	save_phase1_as_prefix varchar(50), -- Table name prefix when saving the data as tables
	-- Phase 2.2 (non-obfuscated aggregate and patient level data) options
	include_extra_cohorts_phase2 bit, -- 0 by default, 1 to include COVID negative, U07.1, and non-admitted cohorts to Phase 2 files
	replace_patient_num bit, -- Replace the patient_num with a unique random number
	output_phase2_as_columns bit, -- Return the data in tables with separate columns per field
	output_phase2_as_csv bit, -- Return the data in tables with a single column containing comma separated values
	save_phase2_as_columns bit, -- Save the data as tables with separate columns per field
	save_phase2_as_prefix varchar(50) -- Table name prefix when saving the data as tables
)
insert into #fource_config
	select 'YOURSITEID', -- siteid
		1, -- race_data_available
		1, -- icu_data_available
		1, -- death_data_available
		'DIAG|ICD9:', -- code_prefix_icd9cm
		'DIAG|ICD10:', -- code_prefix_icd10cm
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
		'dbo.FourCE_', -- save_phase1_as_prefix (don't use "4CE" since it starts with a number)
		-- Phase 2
		0, -- include_extra_cohorts_phase2 (please set to 1 if allowed by your IRB and institution)
		1, -- replace_patient_num
		0, -- output_phase2_as_columns
		0, -- output_phase2_as_csv
		0, -- save_phase2_as_columns
		'dbo.FourCE_' -- save_phase2_as_prefix (don't use "4CE" since it starts with a number)
		

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
create table #fource_code_map (
	code varchar(50) not null,
	local_code varchar(50) not null
)
alter table #fource_code_map add primary key (code, local_code)

-- Inpatient visit codes
-- * The SQL supports using either visit_dimension table or the observation_fact table.
-- * Change the code as needed. Comment out the versions that you do not use.
insert into #fource_code_map
	select '', '' where 1=0
	-- Inpatient visits (from the visit_dimension.inout_cd field)
	union all select 'inpatient_inout_cd', 'I'
	union all select 'inpatient_inout_cd', 'IN'
	-- Inpatient visits (from the visit_dimension.location_cd field)
	union all select 'inpatient_location_cd', 'Inpatient'
	-- ICU visits (from the observation_fact.concept_cd field)
	union all select 'inpatient_concept_cd', 'UMLS:C1547137' -- from ACT ontology

-- ICU visit codes (optional)
-- * The SQL supports using either visit_dimension table or the observation_fact table.
-- * Change the code as needed. Comment out the versions that you do not use.
insert into #fource_code_map
	select '', '' where 1=0
	-- ICU visits (from the visit_dimension.inout_cd field)
	union all select 'icu_inout_cd', 'ICU'
	-- ICU visits (from the visit_dimension.location_cd field)
	union all select 'icu_location_cd', 'ICU'
	-- ICU visits (from the observation_fact.concept_cd field)
	union all select 'icu_concept_cd', 'UMLS:C1547136' -- from ACT ontology

-- Sex codes
insert into #fource_code_map
	select '', '' where 1=0
	-- Sex (from the patient_dimension.sex_cd field)
	union all select 'sex_patient:male', 'M'
	union all select 'sex_patient:male', 'Male'
	union all select 'sex_patient:female', 'F'
	union all select 'sex_patient:female', 'Female'
	-- Sex (from the observation_fact.concept_cd field)
	union all select 'sex_fact:male', 'DEM|SEX:M'
	union all select 'sex_fact:male', 'DEM|SEX:Male'
	union all select 'sex_fact:female', 'DEM|SEX:F'
	union all select 'sex_fact:female', 'DEM|SEX:Female'

-- Race codes (use the code set for your country, comment out other countries)
insert into #fource_code_map
	select '', '' where 1=0
	-------------------------------------------------------------------
	-- Race: United States
	-------------------------------------------------------------------
	-- Race (from the patient_dimension.race_cd field)
	union all select 'race_patient:american_indian', 'NA'
	union all select 'race_patient:asian', 'A'
	union all select 'race_patient:asian', 'AS'
	union all select 'race_patient:black', 'B'
	union all select 'race_patient:hawaiian_pacific_islander', 'H'
	union all select 'race_patient:hawaiian_pacific_islander', 'P'
	union all select 'race_patient:white', 'W'
	union all select 'race_patient:hispanic_latino', 'HL'
	union all select 'race_patient:other', 'O' -- include multiple if no additional information is known
	union all select 'race_patient:no_information', 'NI' -- unknown, not available, missing, refused to answer, not recorded, etc.
	-- Race (from the observation_fact.concept_cd field)
	union all select 'race_fact:american_indian', 'DEM|race:NA'
	union all select 'race_fact:asian', 'DEM|race:A'
	union all select 'race_fact:asian', 'DEM|race:AS'
	union all select 'race_fact:black', 'DEM|race:B'
	union all select 'race_fact:hawaiian_pacific_islander', 'DEM|race:H'
	union all select 'race_fact:hawaiian_pacific_islander', 'DEM|race:P'
	union all select 'race_fact:white', 'DEM|race:W'
	union all select 'race_fact:hispanic_latino', 'DEM|HISP:Y'
	union all select 'race_fact:hispanic_latino', 'DEM|HISPANIC:Y'
	union all select 'race_fact:other', 'DEM|race:O' -- include multiple if no additional information is known
	union all select 'race_fact:no_information', 'DEM|race:NI' -- unknown, not available, missing, refused to answer, not recorded, etc.
	-------------------------------------------------------------------
	-- Race: United Kingdom (Ethnicity)
	-------------------------------------------------------------------
	-- Ethnicity (from the patient_dimension.race_cd field)
	-- union all select 'race_patient:uk_asian', 'Asian' -- Asian or Asian British (Indian, Pakistani, Bangladeshi, Chinese, other Asian background) 
	-- union all select 'race_patient:uk_black', 'Black' -- Black, African, Carribean, or Black British (African/ Caribbean/ any other Black, African or Caribbean background)
	-- union all select 'race_patient:uk_white', 'White' -- White (English/ Welsh/ Scottish/Northern Irish/ British, Irish, Gypsy or Irish Traveller, other White background)
	-- union all select 'race_patient:uk_multiple', 'Multiple' -- Mixed or Multiple ethnic groups (White and Black Caribbean, White and Black African, White and Asian, Any other Mixed or Multiple ethnic background)
	-- union all select 'race_patient:uk_other', 'Other' -- Other ethnic group (Arab, other ethnic group)
	-- union all select 'race_patient:uk_no_information', 'NI' -- unknown, not available, missing, refused to answer, not recorded, etc.
	-------------------------------------------------------------------
	-- Race: Singapore
	-------------------------------------------------------------------
	-- Race (from the patient_dimension.race_cd field)
	-- union all select 'race_patient:singapore_chinese', 'Chinese'
	-- union all select 'race_patient:singapore_malay', 'Malay'
	-- union all select 'race_patient:singapore_indian', 'Indian'
	-- union all select 'race_patient:singapore_other', 'Other'
	-- union all select 'race_patient:singapore_no_information', 'NI' -- unknown, not available, missing, refused to answer, not recorded, etc.
	-------------------------------------------------------------------
	-- Race: Brazil
	-------------------------------------------------------------------
	-- Race (from the patient_dimension.race_cd field)
	-- union all select 'race_patient:brazil_branco', 'Branco'
	-- union all select 'race_patient:brazil_pardo', 'Pardo'
	-- union all select 'race_patient:brazil_preto', 'Preto'
	-- union all select 'race_patient:brazil_indigena', 'Indigena'
	-- union all select 'race_patient:brazil_amarelo', 'Amarelo'
	-- union all select 'race_patient:brazil_no_information', 'NI' -- unknown, not available, missing, refused to answer, not recorded, etc.

-- Codes that indicate a COVID-19 nucleic acid test result (use option #1 and/or option #2)
-- COVID-19 Test Option #1: individual concept_cd values
insert into #fource_code_map
	select 'covidpos', 'LAB|LOINC:COVID19POS'
	union all
	select 'covidneg', 'LAB|LOINC:COVID19NEG'
-- COVID-19 Test Option #2: an ontology path (e.g., COVID ACT "Any Positive Test" path)
insert into #fource_code_map
	select distinct 'covidpos', concept_cd
		from crc.concept_dimension c
		where concept_path like '\ACT\UMLS_C0031437\SNOMED_3947185011\UMLS_C0022885\UMLS_C1335447\%'
			and concept_cd is not null
			and not exists (select * from #fource_code_map m where m.code='covidpos' and m.local_code=c.concept_cd)
	union all
	select distinct 'covidneg', concept_cd
		from crc.concept_dimension c
		where concept_path like '\ACT\UMLS_C0031437\SNOMED_3947185011\UMLS_C0022885\UMLS_C1334932\%'
			and concept_cd is not null
			and not exists (select * from #fource_code_map m where m.code='covidneg' and m.local_code=c.concept_cd)
-- Other codes that indicate confirmed COVID-19 (e.g., ICD-10 code U07.1, but not U07.2 or U07.3)
insert into #fource_code_map
	select 'covidU071', code_prefix_icd10cm+'U07.1'
		from #fource_config
	union all
	select 'covidU071', code_prefix_icd10cm+'U071'
		from #fource_config

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
create table #fource_lab_map (
	fource_loinc varchar(20) not null, 
	fource_lab_units varchar(20) not null, 
	fource_lab_name varchar(100) not null,
	scale_factor float not null, 
	local_lab_code varchar(50) not null, 
	local_lab_units varchar(20) not null, 
	local_lab_name varchar(500) not null
)
alter table #fource_lab_map add primary key (fource_loinc, local_lab_code, local_lab_units)
insert into #fource_lab_map
	select fource_loinc, fource_lab_units, fource_lab_name,
		scale_factor,
		'LAB|LOINC:'+local_lab_code,  -- Change "LOINC:" to your local LOINC code prefix (scheme)
		local_lab_units, local_lab_name
	from (
		select null fource_loinc, null fource_lab_units, null fource_lab_name, 
				null scale_factor, null local_lab_code, null local_lab_units, null local_lab_name
			where 1=0
		union select '1742-6', 'U/L', 'alanine aminotransferase (ALT)', 1, '1742-6', 'U/L', 'YourLocalLabName'
		union select '1751-7', 'g/dL', 'albumin', 1, '1751-7', 'g/dL', 'YourLocalLabName'
		union select '1920-8', 'U/L', 'aspartate aminotransferase (AST)', 1, '1920-8', 'U/L', 'YourLocalLabName'
		union select '1975-2', 'mg/dL', 'total bilirubin', 1, '1975-2', 'mg/dL', 'YourLocalLabName'
		union select '1988-5', 'mg/L', 'C-reactive protein (CRP) (Normal Sensitivity)', 1, '1988-5', 'mg/L', 'YourLocalLabName'
		union select '2019-8', 'mmHg', 'PaCO2', 1, '2019-8', 'mmHg', 'YourLocalLabName'
		union select '2160-0', 'mg/dL', 'creatinine', 1, '2160-0', 'mg/dL', 'YourLocalLabName'
		union select '2276-4', 'ng/mL', 'Ferritin', 1, '2276-4', 'ng/mL', 'YourLocalLabName'
		union select '2532-0', 'U/L', 'lactate dehydrogenase (LDH)', 1, '2532-0', 'U/L', 'YourLocalLabName'
		union select '2703-7', 'mmHg', 'PaO2', 1, '2703-7', 'mmHg', 'YourLocalLabName'
		union select '3255-7', 'mg/dL', 'Fibrinogen', 1, '3255-7', 'mg/dL', 'YourLocalLabName'
		union select '33959-8', 'ng/mL', 'procalcitonin', 1, '33959-8', 'ng/mL', 'YourLocalLabName'
		union select '48065-7', 'ng/mL{FEU}', 'D-dimer (FEU)', 1, '48065-7', 'ng/mL{FEU}', 'YourLocalLabName'
		union select '48066-5', 'ng/mL{DDU}', 'D-dimer (DDU)', 1, '48066-5', 'ng/mL{DDU}', 'YourLocalLabName'
		union select '49563-0', 'ng/mL', 'cardiac troponin (High Sensitivity)', 1, '49563-0', 'ng/mL', 'YourLocalLabName'
		union select '6598-7', 'ug/L', 'cardiac troponin (Normal Sensitivity)', 1, '6598-7', 'ug/L', 'YourLocalLabName'
		union select '5902-2', 's', 'prothrombin time (PT)', 1, '5902-2', 's', 'YourLocalLabName'
		union select '6690-2', '10*3/uL', 'white blood cell count (Leukocytes)', 1, '6690-2', '10*3/uL', 'YourLocalLabName'
		union select '731-0', '10*3/uL', 'lymphocyte count', 1, '731-0', '10*3/uL', 'YourLocalLabName'
		union select '751-8', '10*3/uL', 'neutrophil count', 1, '751-8', '10*3/uL', 'YourLocalLabName'
		union select '777-3', '10*3/uL', 'platelet count', 1, '777-3', '10*3/uL', 'YourLocalLabName'
		union select '34714-6', 'DEFAULT', 'INR', 1, '34714-6', 'DEFAULT', 'YourLocalLabName'
		--Example of listing an additional code for the same lab
		--union select '2019-8', 'mmHg', 'PaCO2', 1, 'LAB:PaCO2', 'mmHg', 'Carbon dioxide partial pressure in arterial blood'
		--Examples of listing different units for the same lab
		--union select '2703-7', 'mmHg', 'PaO2', 10, '2703-7', 'cmHg', 'PaO2'
		--union select '2703-7', 'mmHg', 'PaO2', 25.4, '2703-7', 'inHg', 'PaO2'
		--This will use the given scale factor (in this case 1) for any lab with NULL or empty string units 
		--union select '2703-7', 'mmHg', 'PaO2', 1, '2703-7', 'DEFAULT', 'PaO2 [mmHg]'
	) t

-- Use the concept_dimension table to get an expanded list of local lab codes (optional).
-- This will find paths corresponding to concepts already in the #fource_lab_map table,
-- and then find all the concepts corresponding to child paths. Make sure you update the
-- scale_factor, local_lab_units, and local_lab_name as needed.
-- WARNING: This query might take several minutes to run.
/*
insert into #fource_lab_map
	select distinct l.fource_loinc, l.fource_lab_units, l.fource_lab_name, l.scale_factor, d.concept_cd, l.local_lab_units, l.local_lab_name
	from #fource_lab_map l
		inner join crc.concept_dimension c
			on l.local_lab_code = c.concept_cd
		inner join crc.concept_dimension d
			on d.concept_path like c.concept_path+'%'
	where not exists (
		select *
		from #fource_lab_map t
		where t.fource_loinc = l.fource_loinc and t.local_lab_code = d.concept_cd
	)
*/

-- Use the concept_dimension table to get the local names for labs (optional).
/*
update l
	set l.local_lab_name = c.name_char
	from #fource_lab_map l
		inner join crc.concept_dimension c
			on l.local_lab_code = c.concept_cd
*/

--------------------------------------------------------------------------------
-- Lab mappings report (for debugging lab mappings)
--------------------------------------------------------------------------------
-- Get a list of all the codes and units in the data for 4CE labs since 1/1/2019
create table #fource_lab_units_facts (
	fact_code varchar(50) not null,
	fact_units varchar(50),
	num_facts int,
	mean_value numeric(18,5),
	stdev_value numeric(18,5)
)
insert into #fource_lab_units_facts
	select concept_cd, units_cd, count(*), avg(nval_num), stdev(nval_num)
	from crc.observation_fact with (nolock)
	where concept_cd in (select local_lab_code from #fource_lab_map)
		and start_date >= '1/1/2019'
	group by concept_cd, units_cd
-- Create a table that stores a report about local lab units
create table #fource_lab_map_report (
	fource_loinc varchar(20) not null, 
	fource_lab_units varchar(20), 
	fource_lab_name varchar(100),
	scale_factor float, 
	local_lab_code varchar(50) not null, 
	local_lab_units varchar(20) not null, 
	local_lab_name varchar(500),
	num_facts int,
	mean_value numeric(18,5),
	stdev_value numeric(18,5),
	notes varchar(1000)
)
alter table #fource_lab_map_report add primary key (fource_loinc, local_lab_code, local_lab_units)
-- Compare the #fource_lab_map table to the codes and units in the data
insert into #fource_lab_map_report
	select 
		isnull(m.fource_loinc,a.fource_loinc) fource_loinc,
		isnull(m.fource_lab_units,a.fource_lab_units) fource_lab_units,
		isnull(m.fource_lab_name,a.fource_lab_name) fource_lab_name,
		isnull(m.scale_factor,0) scale_factor,
		isnull(m.local_lab_code,f.fact_code) local_lab_code,
		coalesce(m.local_lab_units,f.fact_units,'(null)') local_lab_units,
		isnull(m.local_lab_name,'(missing)') local_lab_name,
		isnull(f.num_facts,0) num_facts,
		isnull(f.mean_value,-999) mean_value,
		isnull(f.stdev_value,-999) stdev_value,
		(case when scale_factor is not null and num_facts is not null then 'GOOD: Code and units found in the data'
			when m.fource_loinc is not null and c.fact_code is null then 'WARNING: This code from the lab mappings table could not be found in the data'
			when scale_factor is not null then 'WARNING: These local_lab_units in the lab mappings table could not be found in the data'
			else 'WARNING: These local_lab_units exist in the data but are missing from the lab mappings table'
			end) notes
	from #fource_lab_map m
		full outer join #fource_lab_units_facts f
			on f.fact_code=m.local_lab_code and isnull(nullif(f.fact_units,''),'DEFAULT')=m.local_lab_units
		left outer join (
			select distinct fource_loinc, fource_lab_units, fource_lab_name, local_lab_code
			from #fource_lab_map
		) a on a.local_lab_code=f.fact_code
		left outer join (
			select distinct fact_code from #fource_lab_units_facts
		) c on m.local_lab_code=c.fact_code
-- View the results, including counts, to help you check your mappings (optional)
/*
select * from #fource_lab_map_report order by fource_loinc, num_facts desc
*/

--------------------------------------------------------------------------------
-- Medication mappings
-- * Do not change the med_class or add additional medications.
-- * The ATC and RxNorm codes represent the same list of medications.
-- * Use ATC and/or RxNorm, depending on what your institution uses.
--------------------------------------------------------------------------------
create table #fource_med_map (
	med_class varchar(50) not null,
	code_type varchar(10) not null,
	local_med_code varchar(50) not null
)
alter table #fource_med_map add primary key (med_class, code_type, local_med_code)

-- ATC codes (optional)
insert into #fource_med_map
	select m, 'ATC' t, 'ATC:'+c  -- Change "ATC:" to your local ATC code prefix (scheme)
	from (
		-- Don't add or remove drugs
		select 'ACEI' m, c from (select 'C09AA01' c union select 'C09AA02' union select 'C09AA03' union select 'C09AA04' union select 'C09AA05' union select 'C09AA06' union select 'C09AA07' union select 'C09AA08' union select 'C09AA09' union select 'C09AA10' union select 'C09AA11' union select 'C09AA13' union select 'C09AA15' union select 'C09AA16') t
		union select 'ARB', c from (select 'C09CA01' c union select 'C09CA02' union select 'C09CA03' union select 'C09CA04' union select 'C09CA06' union select 'C09CA07' union select 'C09CA08') t
		union select 'COAGA', c from (select 'B01AC04' c union select 'B01AC05' union select 'B01AC07' union select 'B01AC10' union select 'B01AC13' union select 'B01AC16' union select 'B01AC17' union select 'B01AC22' union select 'B01AC24' union select 'B01AC25' union select 'B01AC26') t
		union select 'COAGB', c from (select 'B01AA01' c union select 'B01AA03' union select 'B01AA04' union select 'B01AA07' union select 'B01AA11' union select 'B01AB01' union select 'B01AB04' union select 'B01AB05' union select 'B01AB06' union select 'B01AB07' union select 'B01AB08' union select 'B01AB10' union select 'B01AB12' union select 'B01AE01' union select 'B01AE02' union select 'B01AE03' union select 'B01AE06' union select 'B01AE07' union select 'B01AF01' union select 'B01AF02' union select 'B01AF03' union select 'B01AF04' union select 'B01AX05' union select 'B01AX07') t
		union select 'COVIDVIRAL', c from (select 'J05AE10' c union select 'J05AP01' union select 'J05AR10') t
		union select 'DIURETIC', c from (select 'C03CA01' c union select 'C03CA02' union select 'C03CA03' union select 'C03CA04' union select 'C03CB01' union select 'C03CB02' union select 'C03CC01') t
		union select 'HCQ', c from (select 'P01BA01' c union select 'P01BA02') t
		union select 'ILI', c from (select 'L04AC03' c union select 'L04AC07' union select 'L04AC11' union select 'L04AC14') t
		union select 'INTERFERON', c from (select 'L03AB08' c union select 'L03AB11') t
		union select 'SIANES', c from (select 'M03AC03' c union select 'M03AC09' union select 'M03AC11' union select 'N01AX03' union select 'N01AX10' union select 'N05CD08' union select 'N05CM18') t
		union select 'SICARDIAC', c from (select 'B01AC09' c union select 'C01CA03' union select 'C01CA04' union select 'C01CA06' union select 'C01CA07' union select 'C01CA24' union select 'C01CE02' union select 'C01CX09' union select 'H01BA01' union select 'R07AX01') t
	) t

-- RxNorm codes (optional)
insert into #fource_med_map
	select m, 'RxNorm' t, 'RxNorm:'+c  -- Change "RxNorm:" to your local RxNorm code prefix (scheme)
	from (
		-- Don't add or remove drugs
		select 'ACEI' m, c from (select '36908' c union select '39990' union select '104375' union select '104376' union select '104377' union select '104378' union select '104383' union select '104384' union select '104385' union select '1299896' union select '1299897' union select '1299963' union select '1299965' union select '1435623' union select '1435624' union select '1435630' union select '1806883' union select '1806884' union select '1806890' union select '18867' union select '197884' union select '198187' union select '198188' union select '198189' union select '199351' union select '199352' union select '199353' union select '199622' union select '199707' union select '199708' union select '199709' union select '1998' union select '199816' union select '199817' union select '199931' union select '199937' union select '205326' union select '205707' union select '205778' union select '205779' union select '205780' union select '205781' union select '206277' union select '206313' union select '206764' union select '206765' union select '206766' union select '206771' union select '207780' union select '207792' union select '207800' union select '207820' union select '207891' union select '207892' union select '207893' union select '207895' union select '210671' union select '210672' union select '210673' union select '21102' union select '211535' union select '213482' union select '247516' union select '251856' union select '251857' union select '260333' union select '261257' union select '261258' union select '261962' union select '262076' union select '29046' union select '30131' union select '308607' union select '308609' union select '308612' union select '308613' union select '308962' union select '308963' union select '308964' union select '310063' union select '310065' union select '310066' union select '310067' union select '310422' union select '311353' union select '311354' union select '311734' union select '311735' union select '312311' union select '312312' union select '312313' union select '312748' union select '312749' union select '312750' union select '313982' union select '313987' union select '314076' union select '314077' union select '314203' union select '317173' union select '346568' union select '347739' union select '347972' union select '348000' union select '35208' union select '35296' union select '371001' union select '371254' union select '371506' union select '372007' union select '372274' union select '372614' union select '372945' union select '373293' union select '373731' union select '373748' union select '373749' union select '374176' union select '374177' union select '374938' union select '378288' union select '3827' union select '38454' union select '389182' union select '389183' union select '389184' union select '393442' union select '401965' union select '401968' union select '411434' union select '50166' union select '542702' union select '542704' union select '54552' union select '60245' union select '629055' union select '656757' union select '807349' union select '845488' union select '845489' union select '854925' union select '854927' union select '854984' union select '854986' union select '854988' union select '854990' union select '857169' union select '857171' union select '857183' union select '857187' union select '857189' union select '858804' union select '858806' union select '858810' union select '858812' union select '858813' union select '858815' union select '858817' union select '858819' union select '858821' union select '898687' union select '898689' union select '898690' union select '898692' union select '898719' union select '898721' union select '898723' union select '898725') t
		union select 'ARB', c from (select '118463' c union select '108725' union select '153077' union select '153665' union select '153666' union select '153667' union select '153821' union select '153822' union select '153823' union select '153824' union select '1996253' union select '1996254' union select '199850' union select '199919' union select '200094' union select '200095' union select '200096' union select '205279' union select '205304' union select '205305' union select '2057151' union select '2057152' union select '2057158' union select '206256' union select '213431' union select '213432' union select '214354' union select '261209' union select '261301' union select '282755' union select '284531' union select '310139' union select '310140' union select '311379' union select '311380' union select '314073' union select '349199' union select '349200' union select '349201' union select '349483' union select '351761' union select '351762' union select '352001' union select '352274' union select '370704' union select '371247' union select '372651' union select '374024' union select '374279' union select '374612' union select '378276' union select '389185' union select '484824' union select '484828' union select '484855' union select '52175' union select '577776' union select '577785' union select '577787' union select '598024' union select '615856' union select '639536' union select '639537' union select '639539' union select '639543' union select '69749' union select '73494' union select '83515' union select '83818' union select '979480' union select '979482' union select '979485' union select '979487' union select '979492' union select '979494') t
		union select 'COAGA', c from (select '27518' c union select '10594' union select '108911' union select '1116632' union select '1116634' union select '1116635' union select '1116639' union select '1537034' union select '1537038' union select '1537039' union select '1537045' union select '1656052' union select '1656055' union select '1656056' union select '1656061' union select '1656683' union select '1666332' union select '1666334' union select '1736469' union select '1736470' union select '1736472' union select '1736477' union select '1736478' union select '1737465' union select '1737466' union select '1737468' union select '1737471' union select '1737472' union select '1812189' union select '1813035' union select '1813037' union select '197622' union select '199314' union select '200348' union select '200349' union select '205253' union select '206714' union select '207569' union select '208316' union select '208558' union select '213169' union select '213299' union select '241162' union select '261096' union select '261097' union select '309362' union select '309952' union select '309953' union select '309955' union select '313406' union select '32968' union select '333833' union select '3521' union select '371917' union select '374131' union select '374583' union select '375035' union select '392451' union select '393522' union select '613391' union select '73137' union select '749196' union select '749198' union select '75635' union select '83929' union select '855811' union select '855812' union select '855816' union select '855818' union select '855820') t
		union select 'COAGB', c from (select '2110605' c union select '237057' union select '69528' union select '8150' union select '163426' union select '1037042' union select '1037044' union select '1037045' union select '1037049' union select '1037179' union select '1037181' union select '1110708' union select '1114195' union select '1114197' union select '1114198' union select '1114202' union select '11289' union select '114934' union select '1232082' union select '1232084' union select '1232086' union select '1232088' union select '1241815' union select '1241823' union select '1245458' union select '1245688' union select '1313142' union select '1359733' union select '1359900' union select '1359967' union select '1360012' union select '1360432' union select '1361029' union select '1361038' union select '1361048' union select '1361226' union select '1361568' union select '1361574' union select '1361577' union select '1361607' union select '1361613' union select '1361615' union select '1361853' union select '1362024' union select '1362026' union select '1362027' union select '1362029' union select '1362030' union select '1362048' union select '1362052' union select '1362054' union select '1362055' union select '1362057' union select '1362059' union select '1362060' union select '1362061' union select '1362062' union select '1362063' union select '1362065' union select '1362067' union select '1362824' union select '1362831' union select '1362837' union select '1362935' union select '1362962' union select '1364430' union select '1364434' union select '1364435' union select '1364441' union select '1364445' union select '1364447' union select '1490491' union select '1490493' union select '15202' union select '152604' union select '154' union select '1549682' union select '1549683' union select '1598' union select '1599538' union select '1599542' union select '1599543' union select '1599549' union select '1599551' union select '1599553' union select '1599555' union select '1599557' union select '1656595' union select '1656599' union select '1656760' union select '1657991' union select '1658634' union select '1658637' union select '1658647' union select '1658659' union select '1658690' union select '1658692' union select '1658707' union select '1658717' union select '1658719' union select '1658720' union select '1659195' union select '1659197' union select '1659260' union select '1659263' union select '1723476' union select '1723478' union select '1798389' union select '1804730' union select '1804735' union select '1804737' union select '1804738' union select '1807809' union select '1856275' union select '1856278' union select '1857598' union select '1857949' union select '1927851' union select '1927855' union select '1927856' union select '1927862' union select '1927864' union select '1927866' union select '197597' union select '198349' union select '1992427' union select '1992428' union select '1997015' union select '1997017' union select '204429' union select '204431' union select '205791' union select '2059015' union select '2059017' union select '209081' union select '209082' union select '209083' union select '209084' union select '209086' union select '209087' union select '209088' union select '211763' union select '212123' union select '212124' union select '212155' union select '238722' union select '238727' union select '238729' union select '238730' union select '241112' union select '241113' union select '242501' union select '244230' union select '244231' union select '244239' union select '244240' union select '246018' union select '246019' union select '248140' union select '248141' union select '251272' union select '280611' union select '282479' union select '283855' union select '284458' union select '284534' union select '308351' union select '308769' union select '310710' union select '310713' union select '310723' union select '310732' union select '310733' union select '310734' union select '310739' union select '310741' union select '313410' union select '313732' union select '313733' union select '313734' union select '313735' union select '313737' union select '313738' union select '313739' union select '314013' union select '314279' union select '314280' union select '321208' union select '349308' union select '351111' union select '352081' union select '352102' union select '370743' union select '371679' union select '371810' union select '372012' union select '374319' union select '374320' union select '374638' union select '376834' union select '381158' union select '389189' union select '402248' union select '402249' union select '404141' union select '404142' union select '404143' union select '404144' union select '404146' union select '404147' union select '404148' union select '404259' union select '404260' union select '415379' union select '5224' union select '540217' union select '542824' union select '545076' union select '562130' union select '562550' union select '581236' union select '60819' union select '616862' union select '616912' union select '645887' union select '67031' union select '67108' union select '67109' union select '69646' union select '727382' union select '727383' union select '727384' union select '727559' union select '727560' union select '727562' union select '727563' union select '727564' union select '727565' union select '727566' union select '727567' union select '727568' union select '727718' union select '727719' union select '727722' union select '727723' union select '727724' union select '727725' union select '727726' union select '727727' union select '727728' union select '727729' union select '727730' union select '727778' union select '727831' union select '727832' union select '727834' union select '727838' union select '727851' union select '727859' union select '727860' union select '727861' union select '727878' union select '727880' union select '727881' union select '727882' union select '727883' union select '727884' union select '727888' union select '727892' union select '727920' union select '727922' union select '727926' union select '729968' union select '729969' union select '729970' union select '729971' union select '729972' union select '729973' union select '729974' union select '729976' union select '730002' union select '746573' union select '746574' union select '753111' union select '753112' union select '753113' union select '759595' union select '759596' union select '759597' union select '759598' union select '759599' union select '75960' union select '759600' union select '759601' union select '792060' union select '795798' union select '827000' union select '827001' union select '827003' union select '827069' union select '827099' union select '829884' union select '829885' union select '829886' union select '829888' union select '830698' union select '848335' union select '848339' union select '849297' union select '849298' union select '849299' union select '849300' union select '849301' union select '849312' union select '849313' union select '849317' union select '849333' union select '849337' union select '849338' union select '849339' union select '849340' union select '849341' union select '849342' union select '849344' union select '849699' union select '849702' union select '849710' union select '849712' union select '849715' union select '849718' union select '849722' union select '849726' union select '849764' union select '849770' union select '849776' union select '849814' union select '854228' union select '854232' union select '854235' union select '854236' union select '854238' union select '854239' union select '854241' union select '854242' union select '854245' union select '854247' union select '854248' union select '854249' union select '854252' union select '854253' union select '854255' union select '854256' union select '855288' union select '855290' union select '855292' union select '855296' union select '855298' union select '855300' union select '855302' union select '855304' union select '855306' union select '855308' union select '855312' union select '855314' union select '855316' union select '855318' union select '855320' union select '855322' union select '855324' union select '855326' union select '855328' union select '855332' union select '855334' union select '855336' union select '855338' union select '855340' union select '855342' union select '855344' union select '855346' union select '855348' union select '855350' union select '857253' union select '857255' union select '857257' union select '857259' union select '857261' union select '857645' union select '861356' union select '861358' union select '861360' union select '861362' union select '861363' union select '861364' union select '861365' union select '861366' union select '978713' union select '978715' union select '978717' union select '978718' union select '978719' union select '978720' union select '978721' union select '978722' union select '978723' union select '978725' union select '978727' union select '978733' union select '978735' union select '978736' union select '978737' union select '978738' union select '978740' union select '978741' union select '978744' union select '978745' union select '978746' union select '978747' union select '978755' union select '978757' union select '978759' union select '978761' union select '978777' union select '978778') t
		union select 'COVIDVIRAL', c from (select '108766' c union select '1236627' union select '1236628' union select '1236632' union select '1298334' union select '1359269' union select '1359271' union select '1486197' union select '1486198' union select '1486200' union select '1486202' union select '1486203' union select '1487498' union select '1487500' union select '1863148' union select '1992160' union select '207406' union select '248109' union select '248110' union select '248112' union select '284477' union select '284640' union select '311368' union select '311369' union select '312817' union select '312818' union select '352007' union select '352337' union select '373772' union select '373773' union select '373774' union select '374642' union select '374643' union select '376293' union select '378671' union select '460132' union select '539485' union select '544400' union select '597718' union select '597722' union select '597729' union select '597730' union select '602770' union select '616129' union select '616131' union select '616133' union select '643073' union select '643074' union select '670026' union select '701411' union select '701413' union select '746645' union select '746647' union select '754738' union select '757597' union select '757598' union select '757599' union select '757600' union select '790286' union select '794610' union select '795742' union select '795743' union select '824338' union select '824876' union select '831868' union select '831870' union select '847330' union select '847741' union select '847745' union select '847749' union select '850455' union select '850457' union select '896790' union select '902312' union select '902313' union select '9344') t
		union select 'DIURETIC', c from (select '392534' c union select '4109' union select '392464' union select '33770' union select '104220' union select '104222' union select '1112201' union select '132604' union select '1488537' union select '1546054' union select '1546056' union select '1719285' union select '1719286' union select '1719290' union select '1719291' union select '1727568' union select '1727569' union select '1727572' union select '1729520' union select '1729521' union select '1729523' union select '1729527' union select '1729528' union select '1808' union select '197417' union select '197418' union select '197419' union select '197730' union select '197731' union select '197732' union select '198369' union select '198370' union select '198371' union select '198372' union select '199610' union select '200801' union select '200809' union select '204154' union select '205488' union select '205489' union select '205490' union select '205732' union select '208076' union select '208078' union select '208080' union select '208081' union select '208082' union select '248657' union select '250044' union select '250660' union select '251308' union select '252484' union select '282452' union select '282486' union select '310429' union select '313988' union select '371157' union select '371158' union select '372280' union select '372281' union select '374168' union select '374368' union select '38413' union select '404018' union select '4603' union select '545041' union select '561969' union select '630032' union select '630035' union select '645036' union select '727573' union select '727574' union select '727575' union select '727845' union select '876422' union select '95600') t
		union select 'HCQ', c from (select '1116758' c union select '1116760' union select '1117346' union select '1117351' union select '1117353' union select '1117531' union select '197474' union select '197796' union select '202317' union select '213378' union select '226388' union select '2393' union select '249663' union select '250175' union select '261104' union select '370656' union select '371407' union select '5521' union select '755624' union select '755625' union select '756408' union select '979092' union select '979094') t
		union select 'ILI', c from (select '1441526' c union select '1441527' union select '1441530' union select '1535218' union select '1535242' union select '1535247' union select '1657973' union select '1657974' union select '1657976' union select '1657979' union select '1657980' union select '1657981' union select '1657982' union select '1658131' union select '1658132' union select '1658135' union select '1658139' union select '1658141' union select '1923319' union select '1923332' union select '1923333' union select '1923338' union select '1923345' union select '1923347' union select '2003754' union select '2003755' union select '2003757' union select '2003766' union select '2003767' union select '351141' union select '352056' union select '612865' union select '72435' union select '727708' union select '727711' union select '727714' union select '727715' union select '895760' union select '895764') t
		union select 'INTERFERON', c from (select '120608' c union select '1650893' union select '1650894' union select '1650896' union select '1650922' union select '1650940' union select '1651307' union select '1721323' union select '198360' union select '207059' union select '351270' union select '352297' union select '378926' union select '403986' union select '72257' union select '731325' union select '731326' union select '731328' union select '731330' union select '860244') t
		union select 'SIANES', c from (select '106517' c union select '1087926' union select '1188478' union select '1234995' union select '1242617' union select '1249681' union select '1301259' union select '1313988' union select '1373737' union select '1486837' union select '1535224' union select '1535226' union select '1535228' union select '1535230' union select '1551393' union select '1551395' union select '1605773' union select '1666776' union select '1666777' union select '1666797' union select '1666798' union select '1666800' union select '1666814' union select '1666821' union select '1666823' union select '1718899' union select '1718900' union select '1718902' union select '1718906' union select '1718907' union select '1718909' union select '1718910' union select '1730193' union select '1730194' union select '1730196' union select '1732667' union select '1732668' union select '1732674' union select '1788947' union select '1808216' union select '1808217' union select '1808219' union select '1808222' union select '1808223' union select '1808224' union select '1808225' union select '1808234' union select '1808235' union select '1862110' union select '198383' union select '199211' union select '199212' union select '199775' union select '2050125' union select '2057964' union select '206967' union select '206970' union select '206972' union select '207793' union select '207901' union select '210676' union select '210677' union select '238082' union select '238083' union select '238084' union select '240606' union select '259859' union select '284397' union select '309710' union select '311700' union select '311701' union select '311702' union select '312674' union select '319864' union select '372528' union select '372922' union select '375623' union select '376856' union select '377135' union select '377219' union select '377483' union select '379133' union select '404091' union select '404092' union select '404136' union select '422410' union select '446503' union select '48937' union select '584528' union select '584530' union select '6130' union select '631205' union select '68139' union select '6960' union select '71535' union select '828589' union select '828591' union select '830752' union select '859437' union select '8782' union select '884675' union select '897073' union select '897077' union select '998210' union select '998211') t
		union select 'SICARDIAC', c from (select '7442' c union select '1009216' union select '1045470' union select '1049182' union select '1049184' union select '1052767' union select '106686' union select '106779' union select '106780' union select '1087043' union select '1087047' union select '1090087' union select '1114874' union select '1114880' union select '1114888' union select '11149' union select '1117374' union select '1232651' union select '1232653' union select '1234563' union select '1234569' union select '1234571' union select '1234576' union select '1234578' union select '1234579' union select '1234581' union select '1234584' union select '1234585' union select '1234586' union select '1251018' union select '1251022' union select '1292716' union select '1292731' union select '1292740' union select '1292751' union select '1292887' union select '1299137' union select '1299141' union select '1299145' union select '1299879' union select '1300092' union select '1302755' union select '1305268' union select '1305269' union select '1307224' union select '1358843' union select '1363777' union select '1363785' union select '1363786' union select '1363787' union select '1366958' union select '141848' union select '1490057' union select '1542385' union select '1546216' union select '1546217' union select '1547926' union select '1548673' union select '1549386' union select '1549388' union select '1593738' union select '1658178' union select '1660013' union select '1660014' union select '1660016' union select '1661387' union select '1666371' union select '1666372' union select '1666374' union select '1721536' union select '1743862' union select '1743869' union select '1743871' union select '1743877' union select '1743879' union select '1743938' union select '1743941' union select '1743950' union select '1743953' union select '1745276' union select '1789858' union select '1791839' union select '1791840' union select '1791842' union select '1791854' union select '1791859' union select '1791861' union select '1812167' union select '1812168' union select '1812170' union select '1870205' union select '1870207' union select '1870225' union select '1870230' union select '1870232' union select '1939322' union select '198620' union select '198621' union select '198786' union select '198787' union select '198788' union select '1989112' union select '1989117' union select '1991328' union select '1991329' union select '1999003' union select '1999006' union select '1999007' union select '1999012' union select '204395' union select '204843' union select '209217' union select '2103181' union select '2103182' union select '2103184' union select '211199' union select '211200' union select '211704' union select '211709' union select '211712' union select '211714' union select '211715' union select '212343' union select '212770' union select '212771' union select '212772' union select '212773' union select '238217' union select '238218' union select '238219' union select '238230' union select '238996' union select '238997' union select '238999' union select '239000' union select '239001' union select '241033' union select '242969' union select '244284' union select '245317' union select '247596' union select '247940' union select '260687' union select '309985' union select '309986' union select '309987' union select '310011' union select '310012' union select '310013' union select '310116' union select '310117' union select '310127' union select '310132' union select '311705' union select '312395' union select '312398' union select '313578' union select '313967' union select '314175' union select '347930' union select '351701' union select '351702' union select '351982' union select '359907' union select '3616' union select '3628' union select '372029' union select '372030' union select '372031' union select '373368' union select '373369' union select '373370' union select '373372' union select '373375' union select '374283' union select '374570' union select '376521' union select '377281' union select '379042' union select '387789' union select '392099' union select '393309' union select '3992' union select '404093' union select '477358' union select '477359' union select '52769' union select '542391' union select '542655' union select '542674' union select '562501' union select '562502' union select '562592' union select '584580' union select '584582' union select '584584' union select '584588' union select '602511' union select '603259' union select '603276' union select '603915' union select '617785' union select '669267' union select '672683' union select '672685' union select '672891' union select '692479' union select '700414' union select '704955' union select '705163' union select '705164' union select '705170' union select '727310' union select '727316' union select '727345' union select '727347' union select '727373' union select '727386' union select '727410' union select '727842' union select '727843' union select '727844' union select '746206' union select '746207' union select '7512' union select '8163' union select '827706' union select '864089' union select '880658' union select '8814' union select '883806' union select '891437' union select '891438') t
	) t

-- Remdesivir defined separately since many sites will have custom codes (optional)
insert into #fource_med_map
	select 'REMDESIVIR', 'RxNorm', 'RxNorm:2284718'
	union select 'REMDESIVIR', 'RxNorm', 'RxNorm:2284960'
	union select 'REMDESIVIR', 'Custom', 'ACT|LOCAL:REMDESIVIR'

-- Use the concept_dimension to get an expanded list of medication codes (optional)
-- This will find paths corresponding to concepts already in the #fource_med_map table,
-- and then find all the concepts corresponding to child paths.
-- WARNING: This query might take several minutes to run.
/*
select concept_path, concept_cd
	into #med_paths
	from crc.concept_dimension
	where concept_path like '\ACT\Medications\%'
		and concept_cd in (select concept_cd from crc.observation_fact with (nolock)) 
alter table #med_paths add primary key (concept_path)
insert into #fource_med_map
	select distinct m.med_class, 'Expand', d.concept_cd
	from #fource_med_map m
		inner join crc.concept_dimension c
			on m.local_med_code = c.concept_cd
		inner join #med_paths d
			on d.concept_path like c.concept_path+'%'
	where not exists (
		select *
		from #fource_med_map t
		where t.med_class = m.med_class and t.local_med_code = d.concept_cd
	)
*/

--------------------------------------------------------------------------------
-- Procedure mappings
-- * Do not change the proc_group or add additional procedures.
--------------------------------------------------------------------------------
create table #fource_proc_map (
	proc_group varchar(50) not null,
	code_type varchar(10) not null,
	local_proc_code varchar(50) not null
)
alter table #fource_proc_map add primary key (proc_group, code_type, local_proc_code)

-- CPT4 (United States)
insert into #fource_proc_map
	select p, 'CPT4', 'CPT4:'+c  -- Change "CPT4:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select '44970' c union select '47562' union select '47563' union select '44950' union select '49320' union select '44180' union select '49585' union select '44120') t
		union all select 'EmergencyOrthopedics', c from (select '27245' c union select '27236' union select '27759' union select '24538' union select '11044' union select '27506' union select '22614' union select '27814' union select '63030') t
		union all select 'EmergencyVascularSurgery', c from (select '36247' c) t
		union all select 'EmergencyOBGYN', c from (select '59151' c) t
		union all select 'RenalReplacement', c from (select '90935' c union select '90937' union select '90945') t
		union all select 'SupplementalOxygenSevere', c from (select '94002' c union select '94003' union select '94660' union select '31500') t
		union all select 'ECMO', c from (select '33946' c union select '33947' union select '33951' union select '33952') t
		union all select 'CPR', c from (select '92950' c) t
		union all select 'ArterialCatheter', c from (select '36620' c) t
		union all select 'CTChest', c from (select '71250' c union select '71260' union select '71270') t
		union all select 'Bronchoscopy', c from (select '31645' c) t
		union all select 'CovidVaccine', c from (select '0001A' c union select '0002A' union select '0011A' union select '0012A' union select '0021A' union select '0022A' union select '0031A' union select '91300' union select '91301' union select '91302' union select '91303') t
	) t

-- CCAM (France)
insert into #fource_proc_map
	select p, 'CCAM', 'CCAM:'+c  -- Change "CCAM:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select 'HHFA016' c union select 'HMFC004' union select 'HHFA011' union select 'ZCQC002' union select 'HGPC015' union select 'LMMA006' union select 'LMMA009' union select 'HGFA007' union select 'HGFC021') t
		union all select 'EmergencyOrthopedics', c from (select 'NBCA006' c union select 'NBCA005' union select 'NCCB006' union select 'MBCB001' union select 'NBCA007' union select 'LHDA001' union select 'LHDA002' union select 'NCCA017' union select 'LFFA001' union select 'LDFA003') t
		union all select 'EmergencyOBGYN', c from (select 'JJFC001' c) t
		union all select 'RenalReplacement', c from (select 'JVJF004' c union select 'JVJF005' union select 'JVJF004' union select 'JVJB001' union select 'JVJB002' union select 'JVJF003' union select 'JVJF008') t
		union all select 'SupplementalOxygenSevere', c from (select 'GLMF001' c union select 'GLLD003' union select 'GLLD012' union select 'GLLD019' union select 'GLMP001' union select 'GLLD008' union select 'GLLD015' union select 'GLLD004' union select 'GELD004') t
		union all select 'SupplementalOxygenOther', c from (select 'GLLD017' c) t
		union all select 'ECMO', c from (select 'EQLA002' c union select 'EQQP004' union select 'GLJF010') t
		union all select 'CPR', c from (select 'DKMD001' c union select 'DKMD002') t
		union all select 'ArterialCatheter', c from (select 'ENLF001' c) t
		union all select 'CTChest', c from (select 'ZBQK001' c union select 'ZBQH001') t
		union all select 'Bronchoscopy', c from (select 'GEJE001' c union select 'GEJE003') t
	) t

-- OPCS4 (United Kingdom)
insert into #fource_proc_map
	select p, 'OPCS4', 'OPCS4:'+c  -- Change "OPCS4:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select 'H01' c union select 'Y75.2' union select 'J18' union select 'Y75.2' union select 'J18.2' union select 'Y75.2' union select 'H01' union select 'T43' union select 'T43.8' union select 'T41.3' union select 'T24' union select 'G58.4' union select 'G69.3') t
		union all select 'EmergencyOrthopedics', c from (select 'W24.1' c union select 'W19.1' union select 'W33.6' union select 'W19.2' union select 'V38' union select 'V55.1' union select 'W20.5' union select 'V25.2' union select 'V67.2' union select 'V55.1') t
		union all select 'RenalReplacement', c from (select 'X40.3' c union select 'X40.3' union select 'X40.2' union select 'X40.4' union select 'X40.5' union select 'X40.6' union select 'X40.7' union select 'X40.8' union select 'X40.9') t
		union all select 'SupplementalOxygenSevere', c from (select 'E85.2' c union select 'E85.4' union select 'E85.6' union select 'X56.2') t
		union all select 'SupplementalOxygenOther', c from (select 'X52' c) t
		union all select 'ECMO', c from (select 'X58.1' c union select 'X58.1' union select 'X58.1' union select 'X58.1') t
		union all select 'CPR', c from (select 'X50.3' c) t
		union all select 'CTChest', c from (select 'U07.1' c union select 'Y97.2' union select 'U07.1' union select 'Y97.3' union select 'U07.1' union select 'Y97.1') t
		union all select 'Bronchoscopy', c from (select 'E48.4' c union select 'E50.4') t
	) t

-- OPS (Germany)
insert into #fource_proc_map
	select p, 'OPS', 'OPS:'+c  -- Change "OPS:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select '5-470.1' c union select '5-511.1' union select '5-511.12' union select '5-470' union select '1-694' union select '5-534' union select '5-459.0') t
		union all select 'EmergencyOrthopedics', c from (select '5-790.2f' c union select '5-793.1e' union select '5-790.2m' union select '5-791.6m' union select '5-790.13' union select '5-780.6' union select '5-791.6g' union select '5-836.30' union select '5-032.30') t
		union all select 'RenalReplacement', c from (select '8-854' c union select '8-854' union select '8-857' union select '8-853' union select '8-855' union select '8-856') t
		union all select 'SupplementalOxygenSevere', c from (select '8-716.00' c union select '8-711.0' union select '8-712.0' union select '8-701') t
		union all select 'SupplementalOxygenOther', c from (select '8-72' c) t
		union all select 'ECMO', c from (select '8-852.0' c union select '8-852.30' union select '8-852.31') t
		union all select 'CPR', c from (select '8-771' c) t
		union all select 'CTChest', c from (select '3-202' c union select '3-221') t
	) t

-- TOSP (Singapore)
insert into #fource_proc_map
	select p, 'TOSP', 'TOSP:'+c  -- Change "TOSP:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select 'SF849A' c union select 'SF801G' union select 'SF704G' union select 'SF849A' union select 'SF808A' union select 'SF800A' union select 'SF801A' union select 'SF814A' union select 'SF707I') t
		union all select 'EmergencyOrthopedics', c from (select 'SB811F' c union select 'SB703F' union select 'SB705T' union select 'SB810F' union select 'SB700A' union select 'SB812S') t
		union all select 'EmergencyOBGYN', c from (select 'SI805F' c) t
		union all select 'SupplementalOxygenSevere', c from (select 'SC719T' c union select 'SC720T') t
		union all select 'ECMO', c from (select 'SD721H' c union select 'SD721H' union select 'SD721H' union select 'SD721H') t
		union all select 'ArterialCatheter', c from (select 'SD718A' c) t
		union all select 'Bronchoscopy', c from (select 'SC703B' c union select 'SC704B') t
	) t

-- ICD10AM (Singapore, Australia)
insert into #fource_proc_map
	select p, 'ICD10AM', 'ICD10AM:'+c  -- Change "ICD10AM:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c where 1=0
		union all select 'RenalReplacement', c from (select '13100-00' c union select '13100-00') t
		union all select 'SupplementalOxygenSevere', c from (select '92039-00' c union select '13882-00' union select '13882-01' union select '92038-00') t
		union all select 'SupplementalOxygenOther', c from (select '92044-00' c) t
		union all select 'CPR', c from (select '92052-00' c) t
	) t

-- CBHPM (Brazil-TUSS)
insert into #fource_proc_map
	select p, 'CBHPM', 'CBHPM:'+c  -- Change "CBHPM:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select '31003079' c union select '31005497' union select '31005470' union select '31003079' union select '31009166') t
		union all select 'EmergencyOrthopedics', c from (select '30725119' c union select '30725160' union select '30727138' union select '40803104' union select '30715016' union select '30715199') t
		union all select 'EmergencyOBGYN', c from (select '31309186' c) t
		union all select 'RenalReplacement', c from (select '30909023' c union select '30909031' union select '31008011') t
		union all select 'SupplementalOxygenSevere', c from (select '20203012' c union select '20203012' union select '40202445') t
		union all select 'Bronchoscopy', c from (select '40201058' c) t
	) t

-- ICD9Proc
insert into #fource_proc_map
	select p, 'ICD9', 'ICD9:'+c  -- Change "ICD9:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select '47.01' c union select '51.23' union select '47.0' union select '54.51' union select '53.4') t
		union all select 'EmergencyOrthopedics', c from (select '79.11' c union select '79.6' union select '79.35' union select '81.03' union select '81.05' union select '81.07' union select '79.36') t
		union all select 'EmergencyOBGYN', c from (select '66.62' c) t
		union all select 'RenalReplacement', c from (select '39.95' c union select '39.95') t
		union all select 'SupplementalOxygenSevere', c from (select '93.90' c union select '96.70' union select '96.71' union select '96.72' union select '96.04') t
		union all select 'SupplementalOxygenOther', c from (select '93.96' c) t
		union all select 'ECMO', c from (select '39.65' c union select '39.65' union select '39.65' union select '39.65') t
		union all select 'CPR', c from (select '99.60' c) t
		union all select 'ArterialCatheter', c from (select '38.91' c) t
		union all select 'CTChest', c from (select '87.41' c union select '87.41' union select '87.41') t
		union all select 'Bronchoscopy', c from (select '33.22' c union select '33.23') t
	) t

-- ICD10-PCS
insert into #fource_proc_map
	select p, 'ICD10', 'ICD10:'+c  -- Change "ICD10:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select '0DBJ4ZZ' c union select '0DTJ4ZZ' union select '0FB44ZZ' union select '0FB44ZX' union select '0DBJ0ZZ' union select '0DTJ0ZZ' union select '0DJU4ZZ' union select '0DN84ZZ' union select '0DNE4ZZ') t
		union all select 'EmergencyOrthopedics', c from (select '0QQ60ZZ' c union select '0QQ70ZZ' union select '0QH806Z' union select '0QH906Z') t
		union all select 'SupplementalOxygenSevere', c from (select '5A19054' c union select '5A0935Z' union select '5A0945Z' union select '5A0955Z' union select '5A09357' union select '0BH17EZ') t
		union all select 'ECMO', c from (select '5A1522H' c union select '5A1522G') t
		union all select 'CTChest', c from (select 'BW24' c union select 'BW24Y0Z' union select 'BW24YZZ') t
	) t

-- SNOMED
insert into #fource_proc_map
	select p, 'SNOMED', 'SNOMED:'+c  -- Change "SNOMED:" to your local RxNorm code prefix (scheme)
	from (
		select '' p, '' c where 1=0
		union all select 'EmergencyGeneralSurgery', c from (select '174041007' c union select '45595009' union select '20630000' union select '80146002' union select '450435004' union select '18433007' union select '5789003' union select '44946007' union select '359572002') t
		union all select 'EmergencyOrthopedics', c from (select '179097007' c union select '179018001' union select '73156009' union select '2480009' union select '36939002' union select '55705006' union select '439756000' union select '302129007' union select '231045009' union select '3968003' union select '260648008' union select '178619000') t
		union all select 'EmergencyVascularSurgery', c from (select '392247006' c) t
		union all select 'EmergencyOBGYN', c from (select '63596003' c union select '61893009') t
		union all select 'RenalReplacement', c from (select '302497006' c union select '302497006') t
		union all select 'SupplementalOxygenSevere', c from (select '428311008' c union select '410210009' union select '409025002' union select '47545007' union select '16883004') t
		union all select 'SupplementalOxygenOther', c from (select '57485005' c) t
		union all select 'ECMO', c from (select '786453001' c union select '786451004') t
		union all select 'CPR', c from (select '150819003' c) t
		union all select 'ArterialCatheter', c from (select '392248001' c) t
		union all select 'CTChest', c from (select '395081000119108' c union select '75385009' union select '169069000') t
		union all select 'Bronchoscopy', c from (select '10847001' c union select '68187007') t
	) t

-- Use the concept_dimension to get an expanded list of medication codes (optional)
-- This will find paths corresponding to concepts already in the #fource_med_map table,
-- and then find all the concepts corresponding to child paths.
-- WARNING: This query might take several minutes to run.
/*
select concept_path, concept_cd
	into #med_paths
	from crc.concept_dimension
	where concept_path like '\ACT\Medications\%'
		and concept_cd in (select concept_cd from crc.observation_fact with (nolock)) 
alter table #med_paths add primary key (concept_path)
insert into #fource_med_map
	select distinct m.med_class, 'Expand', d.concept_cd
	from #fource_med_map m
		inner join crc.concept_dimension c
			on m.local_med_code = c.concept_cd
		inner join #med_paths d
			on d.concept_path like c.concept_path+'%'
	where not exists (
		select *
		from #fource_med_map t
		where t.med_class = m.med_class and t.local_med_code = d.concept_cd
	)
*/

--------------------------------------------------------------------------------
-- Multisystem Inflammatory Syndrome in Children (MIS-C) (optional)
-- * Write a custom query to populate this table with the patient_num's of
-- * children who develop MIS-C and their first MIS-C diagnosis date.
--------------------------------------------------------------------------------
create table #fource_misc (
	patient_num int not null,
	misc_date date not null
)
alter table #fource_misc add primary key (patient_num)
insert into #fource_misc
	select -1, '1/1/1900' where 1=0
	--Replace with a list of patients and MIS-C diagnosis dates
	--union all select 1, '3/1/2020'
	--union all select 2, '4/1/2020'

--------------------------------------------------------------------------------
-- Cohorts
-- * In general, use the default values that select patients who were admitted
-- * with a positive COVID test result, broken out in three-month blocks.
-- * Modify this table only if you are working on a specific project that
-- * has defined custom patient cohorts to analyze.
--------------------------------------------------------------------------------
create table #fource_cohort_config (
	cohort varchar(50) not null,
	include_in_phase1 int, -- 1 = include the cohort in the phase 1 output, otherwise 0
	include_in_phase2 int, -- 1 = include the cohort in the phase 2 output and saved files, otherwise 0
	source_data_updated_date date, -- the date your source data were last updated; set to NULL to use the value in the #fource_config table
	earliest_adm_date date, -- the earliest possible admission date allowed in this cohort (NULL if no minimum date)
	latest_adm_date date -- the lastest possible admission date allowed this cohort (NULL if no maximum date)
)
alter table #fource_cohort_config add primary key (cohort)

insert into #fource_cohort_config
	select 'PosAdm2020Q1', 1, 1, NULL, '1/1/2020', '3/31/2020'
	union all select 'PosAdm2020Q2', 1, 1, NULL, '4/1/2020', '6/30/2020'
	union all select 'PosAdm2020Q3', 1, 1, NULL, '7/1/2020', '9/30/2020'
	union all select 'PosAdm2020Q4', 1, 1, NULL, '10/1/2020', '12/31/2020'
	union all select 'PosAdm2021Q1', 1, 1, NULL, '1/1/2021', '3/31/2021'
	union all select 'PosAdm2021Q2', 1, 1, NULL, '4/1/2021', '6/30/2021'
	union all select 'PosAdm2021Q3', 1, 1, NULL, '7/1/2021', '9/30/2021'
	union all select 'PosAdm2021Q4', 1, 1, NULL, '10/1/2021', '12/31/2021'

-- Assume the data were updated on the date this script is run if source_data_updated_date is null
update #fource_cohort_config
	set source_data_updated_date = isnull((select source_data_updated_date from #fource_config),cast(GetDate() as date))
	where source_data_updated_date is null



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
create table #fource_covid_tests (
	patient_num int not null,
	test_result varchar(10) not null,
	test_date date not null
)
alter table #fource_covid_tests add primary key (patient_num, test_result, test_date)
insert into #fource_covid_tests
	select distinct f.patient_num, m.code, cast(start_date as date)
		from crc.observation_fact f with (nolock)
			inner join #fource_code_map m
				on f.concept_cd = m.local_code and m.code in ('covidpos','covidneg','covidU071')

--------------------------------------------------------------------------------
-- Create a list of patient admission dates.
--------------------------------------------------------------------------------
create table #fource_admissions (
	patient_num int not null,
	admission_date date not null,
	discharge_date date not null
)
alter table #fource_admissions add primary key (patient_num, admission_date, discharge_date)
insert into #fource_admissions
	select distinct patient_num, cast(start_date as date), isnull(cast(end_date as date),'1/1/2199') -- a very future date for missing discharge dates
	from (
		-- Select by inout_cd
		select patient_num, start_date, end_date
			from crc.visit_dimension
			where start_date >= '1/1/2019'
				and patient_num in (select patient_num from #fource_covid_tests)
				and inout_cd in (select local_code from #fource_code_map where code = 'inpatient_inout_cd')
		union all
		-- Select by location_cd
		select patient_num, start_date, end_date
			from crc.visit_dimension v
			where start_date >= '1/1/2019'
				and patient_num in (select patient_num from #fource_covid_tests)
				and location_cd in (select local_code from #fource_code_map where code = 'inpatient_location_cd')
		union all
		-- Select by concept_cd
		select f.patient_num, f.start_date, isnull(f.end_date,v.end_date)
			from crc.observation_fact f
				inner join crc.visit_dimension v
					on v.encounter_num=f.encounter_num and v.patient_num=f.patient_num
			where f.start_date >= '1/1/2019'
				and f.patient_num in (select patient_num from #fource_covid_tests)
				and f.concept_cd in (select local_code from #fource_code_map where code = 'inpatient_concept_cd')
	) t
-- remove vists that end before they start
delete from #fource_admissions where discharge_date < admission_date

--------------------------------------------------------------------------------
-- Create a list of dates where patients were in the ICU.
--------------------------------------------------------------------------------
create table #fource_icu (
	patient_num int not null,
	start_date date not null,
	end_date date not null
)
alter table #fource_icu add primary key (patient_num, start_date, end_date)
if exists (select * from #fource_config where icu_data_available = 1)
begin
	insert into #fource_icu
		select distinct patient_num, cast(start_date as date), isnull(cast(end_date as date),'1/1/2199') -- a very future date for missing end dates
		from (
			-- Select by inout_cd
			select patient_num, start_date, end_date
				from crc.visit_dimension
				where start_date >= '1/1/2019'
					and patient_num in (select patient_num from #fource_covid_tests)
					and inout_cd in (select local_code from #fource_code_map where code = 'icu_inout_cd')
			union all
			-- Select by location_cd
			select patient_num, start_date, end_date
				from crc.visit_dimension v
				where start_date >= '1/1/2019'
					and patient_num in (select patient_num from #fource_covid_tests)
					and location_cd in (select local_code from #fource_code_map where code = 'icu_location_cd')
			union all
			-- Select by concept_cd
			select f.patient_num, f.start_date, isnull(f.end_date,v.end_date)
				from crc.observation_fact f
					inner join crc.visit_dimension v
						on v.encounter_num=f.encounter_num and v.patient_num=f.patient_num
				where f.start_date >= '1/1/2019'
					and f.patient_num in (select patient_num from #fource_covid_tests)
					and f.concept_cd in (select local_code from #fource_code_map where code = 'icu_concept_cd')
		) t
end
-- remove vists that end before they start
delete from #fource_icu where end_date < start_date

--------------------------------------------------------------------------------
-- Create a list of dates when patients died.
--------------------------------------------------------------------------------
create table #fource_death (
	patient_num int not null,
	death_date date not null
)
alter table #fource_death add primary key (patient_num)
if exists (select * from #fource_config where death_data_available = 1)
begin
	-- The death_date is estimated later in the SQL if it is null here.
	insert into #fource_death
		select patient_num, isnull(death_date,'1/1/1900') 
		from crc.patient_dimension
		where (death_date is not null or vital_status_cd in ('Y'))
			and patient_num in (select patient_num from #fource_covid_tests)
end



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
create table #fource_first_covid_tests (
	patient_num int not null,
	first_pos_date date,
	first_neg_date date,
	first_U071_date date
)
alter table #fource_first_covid_tests add primary key (patient_num)
insert into #fource_first_covid_tests
	select patient_num,
			min(case when test_result='covidpos' then test_date else null end),
			min(case when test_result='covidneg' then test_date else null end),
			min(case when test_result='covidU071' then test_date else null end)
		from #fource_covid_tests
		group by patient_num

--------------------------------------------------------------------------------
-- Get the list of patients who will be in the cohorts.
-- By default, these will be patients who had an admission between 7 days before
--   and 14 days after their first covid positive test date.
--------------------------------------------------------------------------------
create table #fource_cohort_patients (
	cohort varchar(50) not null,
	patient_num int not null,
	admission_date date not null,
	source_data_updated_date date not null,
	severe int not null,
	severe_date date,
	death_date date
)
alter table #fource_cohort_patients add primary key (patient_num, cohort)
insert into #fource_cohort_patients (cohort, patient_num, admission_date, source_data_updated_date, severe)
	select c.cohort, t.patient_num, t.admission_date, c.source_data_updated_date, 0
	from #fource_cohort_config c,
		(
			select t.patient_num, min(a.admission_date) admission_date
			from #fource_first_covid_tests t
				inner join #fource_admissions a
					on t.patient_num=a.patient_num
						and datediff(dd,t.first_pos_date,a.admission_date) between -7 and 14
			where t.first_pos_date is not null
			group by t.patient_num
		) t
	where c.cohort like 'PosAdm%'
		and t.admission_date >= isnull(c.earliest_adm_date,t.admission_date)
		and t.admission_date <= isnull(c.latest_adm_date,t.admission_date)
		and t.admission_date <= isnull(c.source_data_updated_date,t.admission_date)

--------------------------------------------------------------------------------
-- Add optional cohorts that contain all patients tested for COVID-19
--------------------------------------------------------------------------------
if exists (select * from #fource_config where include_extra_cohorts_phase1=1 or include_extra_cohorts_phase2=1)
begin
	-- Create cohorts for patients who were admitted
	insert into #fource_cohort_config
		-- Patients with a U07.1 code, no recorded positive test result, and were admitted
		select replace(c.cohort,'PosAdm','U071Adm'), 
				g.include_extra_cohorts_phase1, g.include_extra_cohorts_phase2,
				c.source_data_updated_date, c.earliest_adm_date, c.latest_adm_date
			from #fource_cohort_config c cross apply #fource_config g
			where c.cohort like 'PosAdm%'
		-- Patients who have no U07.1 code, no recorded positive test result, a negative test result, and were admitted
		union all
		select replace(c.cohort,'PosAdm','NegAdm'), 
				g.include_extra_cohorts_phase1, g.include_extra_cohorts_phase2,
				c.source_data_updated_date, c.earliest_adm_date, c.latest_adm_date
			from #fource_cohort_config c cross apply #fource_config g
			where c.cohort like 'PosAdm%'

	-- Add the patients for those cohorts
	insert into #fource_cohort_patients (cohort, patient_num, admission_date, source_data_updated_date, severe)
		select c.cohort, t.patient_num, t.admission_date, c.source_data_updated_date, 0
		from #fource_cohort_config c,
			(
				select t.patient_num, 'U071Adm' cohort, min(a.admission_date) admission_date
					from #fource_first_covid_tests t
						inner join #fource_admissions a
							on t.patient_num=a.patient_num
								and datediff(dd,t.first_U071_date,a.admission_date) between -7 and 14
					where t.first_U071_date is not null and t.first_pos_date is null
					group by t.patient_num
				union all
				select t.patient_num, 'NegAdm' cohort, min(a.admission_date) admission_date
					from #fource_first_covid_tests t
						inner join #fource_admissions a
							on t.patient_num=a.patient_num
								and datediff(dd,t.first_neg_date,a.admission_date) between -7 and 14
					where t.first_neg_date is not null and t.first_U071_date is null and t.first_pos_date is null
					group by t.patient_num
			) t
		where c.cohort like t.cohort+'%'
			and t.admission_date >= isnull(c.earliest_adm_date,t.admission_date)
			and t.admission_date <= isnull(c.latest_adm_date,t.admission_date)
			and t.admission_date <= isnull(c.source_data_updated_date,t.admission_date)

	-- Create cohorts for patients who were not admitted
	insert into #fource_cohort_config
		select replace(c.cohort,'Adm','NotAdm'), 
				g.include_extra_cohorts_phase1, g.include_extra_cohorts_phase2,
				c.source_data_updated_date, c.earliest_adm_date, c.latest_adm_date
			from #fource_cohort_config c cross apply #fource_config g
			where c.cohort like 'PosAdm%' or c.cohort like 'NegAdm%' or c.cohort like 'U071Adm%'

	-- Add the patients for those cohorts using the test or diagnosis date as the "admission" (index) date
	insert into #fource_cohort_patients (cohort, patient_num, admission_date, source_data_updated_date, severe)
		select c.cohort, t.patient_num, t.first_pos_date, c.source_data_updated_date, 0
			from #fource_cohort_config c
				cross join #fource_first_covid_tests t
			where c.cohort like 'PosNotAdm%'
				and t.first_pos_date is not null
				and t.first_pos_date >= isnull(c.earliest_adm_date,t.first_pos_date)
				and t.first_pos_date <= isnull(c.latest_adm_date,t.first_pos_date)
				and t.first_pos_date <= isnull(c.source_data_updated_date,t.first_pos_date)
				and t.patient_num not in (select patient_num from #fource_cohort_patients)
		union all
		select c.cohort, t.patient_num, t.first_U071_date, c.source_data_updated_date, 0
			from #fource_cohort_config c
				cross join #fource_first_covid_tests t
			where c.cohort like 'U071NotAdm%'
				and t.first_pos_date is null
				and t.first_U071_date is not null
				and t.first_U071_date >= isnull(c.earliest_adm_date,t.first_U071_date)
				and t.first_U071_date <= isnull(c.latest_adm_date,t.first_U071_date)
				and t.first_U071_date <= isnull(c.source_data_updated_date,t.first_U071_date)
				and t.patient_num not in (select patient_num from #fource_cohort_patients)
		union all
		select c.cohort, t.patient_num, t.first_neg_date, c.source_data_updated_date, 0
			from #fource_cohort_config c
				cross join #fource_first_covid_tests t
			where c.cohort like 'NegNotAdm%'
				and t.first_pos_date is null
				and t.first_U071_date is null
				and t.first_neg_date is not null
				and t.first_neg_date >= isnull(c.earliest_adm_date,t.first_neg_date)
				and t.first_neg_date <= isnull(c.latest_adm_date,t.first_neg_date)
				and t.first_neg_date <= isnull(c.source_data_updated_date,t.first_neg_date)
				and t.patient_num not in (select patient_num from #fource_cohort_patients)
end

--------------------------------------------------------------------------------
-- Add additional custom cohorts here
--------------------------------------------------------------------------------

-- My custom cohorts


--******************************************************************************
--******************************************************************************
--*** Create a table of patient observations
--******************************************************************************
--******************************************************************************


-- Get a distinct list of patients
create table #fource_patients (
	patient_num int not null,
	first_admission_date date not null
)
alter table #fource_patients add primary key (patient_num)
insert into #fource_patients
	select patient_num, min(admission_date)
		from #fource_cohort_patients
		group by patient_num
		
-- Create the table to store the observations
create table #fource_observations (
	cohort varchar(50) not null,
	patient_num int not null,
	severe int not null,
	concept_type varchar(50) not null,
	concept_code varchar(50) not null,
	calendar_date date not null,
	days_since_admission int not null,
	value numeric(18,5) not null,
	logvalue numeric(18,10) not null
)
alter table #fource_observations add primary key (cohort, patient_num, concept_type, concept_code, days_since_admission)

--------------------------------------------------------------------------------
-- Add covid tests
--------------------------------------------------------------------------------
insert into #fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select distinct
		p.cohort,
		p.patient_num,
		p.severe,
		'COVID-TEST',
		t.test_result,
		t.test_date,
		datediff(dd,p.admission_date,t.test_date),
		-999,
		-999
 	from #fource_cohort_patients p
		inner join #fource_covid_tests t
			on p.patient_num=t.patient_num

--------------------------------------------------------------------------------
-- Add children who develop MIS-C
--------------------------------------------------------------------------------
insert into #fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select distinct
		p.cohort,
		p.patient_num,
		p.severe,
		'COVID-MISC',
		'misc',
		cast(f.misc_date as date),
		datediff(dd,p.admission_date,cast(f.misc_date as date)),
		-999,
		-999
 	from #fource_cohort_patients p
		inner join #fource_misc f with (nolock)
			on p.patient_num=f.patient_num

--------------------------------------------------------------------------------
-- Add diagnoses (ICD9) going back 365 days
--------------------------------------------------------------------------------
insert into #fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select distinct
		p.cohort,
		p.patient_num,
		p.severe,
		'DIAG-ICD9',
		substring(f.concept_cd, len(code_prefix_icd9cm)+1, 999),
		cast(f.start_date as date),
		datediff(dd,p.admission_date,cast(f.start_date as date)),
		-999,
		-999
 	from #fource_config x
		cross join crc.observation_fact f with (nolock)
		inner join #fource_cohort_patients p 
			on f.patient_num=p.patient_num 
				and cast(f.start_date as date) between dateadd(dd,-365,p.admission_date) and p.source_data_updated_date
	where concept_cd like code_prefix_icd9cm+'%' and code_prefix_icd9cm<>''

--------------------------------------------------------------------------------
-- Add diagnoses (ICD10) going back 365 days
--------------------------------------------------------------------------------
insert into #fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select distinct
		p.cohort,
		p.patient_num, 
		p.severe,
		'DIAG-ICD10',
		substring(f.concept_cd, len(code_prefix_icd10cm)+1, 999),
		cast(f.start_date as date),
		datediff(dd,p.admission_date,cast(f.start_date as date)),
		-999,
		-999
 	from #fource_config x
		cross join crc.observation_fact f with (nolock)
		inner join #fource_cohort_patients p 
			on f.patient_num=p.patient_num 
				and cast(f.start_date as date) between dateadd(dd,-365,p.admission_date) and p.source_data_updated_date
	where concept_cd like code_prefix_icd10cm+'%' and code_prefix_icd10cm<>''

--------------------------------------------------------------------------------
-- Add medications (Med Class) going back 365 days
--------------------------------------------------------------------------------
insert into #fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select distinct
		p.cohort,
		p.patient_num,
		p.severe,
		'MED-CLASS',
		m.med_class,	
		cast(f.start_date as date),
		datediff(dd,p.admission_date,cast(f.start_date as date)),
		-999,
		-999
	from #fource_med_map m
		inner join crc.observation_fact f with (nolock)
			on f.concept_cd = m.local_med_code
		inner join #fource_cohort_patients p 
			on f.patient_num=p.patient_num 
				and cast(f.start_date as date) between dateadd(dd,-365,p.admission_date) and p.source_data_updated_date

--------------------------------------------------------------------------------
-- Add labs (LOINC) going back 60 days (two months)
--------------------------------------------------------------------------------
insert into #fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select p.cohort,
		p.patient_num,
		p.severe,
		'LAB-LOINC',		
		l.fource_loinc,
		cast(f.start_date as date),
		datediff(dd,p.admission_date,cast(f.start_date as date)),
		avg(f.nval_num*l.scale_factor),
		log(avg(f.nval_num*l.scale_factor) + 0.5) -- natural log (ln), not log base 10; using log(avg()) rather than avg(log()) on purpose
	from #fource_lab_map l
		inner join crc.observation_fact f with (nolock)
			on f.concept_cd=l.local_lab_code and isnull(nullif(f.units_cd,''),'DEFAULT')=l.local_lab_units
		inner join #fource_cohort_patients p 
			on f.patient_num=p.patient_num
	where l.local_lab_code is not null
		and f.nval_num is not null
		and f.nval_num >= 0
		and cast(f.start_date as date) between dateadd(dd,-60,p.admission_date) and p.source_data_updated_date
	group by p.cohort, p.patient_num, p.severe, p.admission_date, cast(f.start_date as date), l.fource_loinc

--------------------------------------------------------------------------------
-- Add procedures (Proc Groups) going back 365 days
--------------------------------------------------------------------------------
insert into #fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	select distinct
		p.cohort,
		p.patient_num,
		p.severe,
		'PROC-GROUP',
		x.proc_group,
		cast(f.start_date as date),
		datediff(dd,p.admission_date,cast(f.start_date as date)),
		-999,
		-999
 	from #fource_proc_map x
		inner join crc.observation_fact f with (nolock)
			on f.concept_cd like x.local_proc_code
		inner join #fource_cohort_patients p 
			on f.patient_num=p.patient_num 
	where x.local_proc_code is not null
		and cast(f.start_date as date) between dateadd(dd,-365,p.admission_date) and p.source_data_updated_date

--------------------------------------------------------------------------------
-- Flag observations that contribute to the disease severity definition
--------------------------------------------------------------------------------
insert into #fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
	-- Any PaCO2 or PaO2 lab test
	select cohort, patient_num, severe, 'SEVERE-LAB' concept_type, 'BloodGas' concept_code, calendar_date, days_since_admission, avg(value), avg(logvalue)
		from #fource_observations
		where concept_type='LAB-LOINC' and concept_code in ('2019-8','2703-7')
		group by cohort, patient_num, severe, calendar_date, days_since_admission
	-- Acute respiratory distress syndrome (diagnosis)
	union all
	select distinct cohort, patient_num, severe, 'SEVERE-DIAG' concept_type, 'ARDS' concept_code, calendar_date, days_since_admission, value, logvalue
		from #fource_observations
		where (concept_type='DIAG-ICD9' and concept_code in ('518.82','51882'))
			or (concept_type='DIAG-ICD10' and concept_code in ('J80'))
	-- Ventilator associated pneumonia (diagnosis)
	union all
	select distinct cohort, patient_num, severe, 'SEVERE-DIAG' concept_type, 'VAP' concept_code, calendar_date, days_since_admission, value, logvalue
		from #fource_observations
		where (concept_type='DIAG-ICD9' and concept_code in ('997.31','99731'))
			or (concept_type='DIAG-ICD10' and concept_code in ('J95.851','J95851'))


--******************************************************************************
--******************************************************************************
--*** Determine which patients had severe disease or died
--******************************************************************************
--******************************************************************************


--------------------------------------------------------------------------------
-- Flag the patients who had severe disease with 30 days of admission.
--------------------------------------------------------------------------------
update p
	set p.severe = 1, p.severe_date = s.severe_date
	from #fource_cohort_patients p
		inner join (
			select f.cohort, f.patient_num, min(f.calendar_date) severe_date
			from #fource_observations f
			where f.days_since_admission between 0 and 30
				and (
					-- Any severe lab or diagnosis
					(f.concept_type in ('SEVERE-LAB','SEVERE-DIAG'))
					-- Any severe medication
					or (f.concept_type='MED-CLASS' and f.concept_code in ('SIANES','SICARDIAC'))
					-- Any severe procedure
					or (f.concept_type='PROC-GROUP' and f.concept_code in ('SupplementalOxygenSevere','ECMO'))
				)
			group by f.cohort, f.patient_num
		) s on p.cohort=s.cohort and p.patient_num=s.patient_num
-- Flag the severe patients in the observations table
update f
	set f.severe=1
	from #fource_observations f
		inner join #fource_cohort_patients p
			on f.cohort=p.cohort and f.patient_num=p.patient_num
	where p.severe=1

--------------------------------------------------------------------------------
-- Add death dates to patients who have died.
--------------------------------------------------------------------------------
if exists (select * from #fource_config where death_data_available = 1)
begin
	-- Add the original death date.
	update c
		set c.death_date = (
			case when p.death_date > isnull(c.severe_date,c.admission_date) 
			then cast(p.death_date as date)
			else isnull(c.severe_date,c.admission_date) end)
		from #fource_cohort_patients c
			inner join #fource_death p
				on p.patient_num = c.patient_num
	-- Check that there aren't more recent facts for the deceased patients.
	update c
		set c.death_date = d.death_date
		from #fource_cohort_patients c
			inner join (
				select p.patient_num, cast(max(f.calendar_date) as date) death_date
				from #fource_cohort_patients p
					inner join #fource_observations f
						on f.cohort=p.cohort and f.patient_num=p.patient_num
				where p.death_date is not null and f.calendar_date > p.death_date
				group by p.cohort, p.patient_num
			) d on c.patient_num = d.patient_num
	-- Make sure the death date is not after the source data updated date
	update #fource_cohort_patients
		set death_date = null
		where death_date > source_data_updated_date
end


--******************************************************************************
--******************************************************************************
--*** For each cohort, create a list of dates since the first case.
--******************************************************************************
--******************************************************************************


create table #fource_date_list (
	cohort varchar(50) not null,
	d date not null
)
alter table #fource_date_list add primary key (cohort, d)
;with n as (
	select 0 n union all select 1 union all select 2 union all select 3 union all select 4 
	union all select 5 union all select 6 union all select 7 union all select 8 union all select 9
)
insert into #fource_date_list
	select l.cohort, d
	from (
		select cohort, isnull(cast(dateadd(dd,a.n+10*b.n+100*c.n,p.s) as date),'1/1/2020') d
		from (
			select cohort, min(admission_date) s 
			from #fource_cohort_patients 
			group by cohort
		) p cross join n a cross join n b cross join n c
	) l inner join #fource_cohort_config f on l.cohort=f.cohort
	where d<=f.source_data_updated_date



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
create table #fource_LocalPatientClinicalCourse (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	patient_num int not null,
	days_since_admission int not null,
	calendar_date date not null,
	in_hospital int not null,
	severe int not null,
	in_icu int not null,
	dead int not null
)
alter table #fource_LocalPatientClinicalCourse add primary key (cohort, patient_num, days_since_admission, siteid)
-- Get the list of dates and flag the ones where the patients were severe or deceased
insert into #fource_LocalPatientClinicalCourse (siteid, cohort, patient_num, days_since_admission, calendar_date, in_hospital, severe, in_icu, dead)
	select '', p.cohort, p.patient_num, 
		datediff(dd,p.admission_date,d.d) days_since_admission,
		d.d calendar_date,
		0 in_hospital,
		max(case when p.severe=1 and d.d>=p.severe_date then 1 else 0 end) severe,
		max(case when x.icu_data_available=0 then -999 else 0 end) in_icu,
		max(case when x.death_data_available=0 then -999 
			when p.death_date is not null and d.d>=p.death_date then 1 
			else 0 end) dead
	from #fource_config x
		cross join #fource_cohort_patients p
		inner join #fource_date_list d
			on p.cohort=d.cohort and d.d>=p.admission_date
	group by p.cohort, p.patient_num, p.admission_date, d.d
-- Flag the days when the patients was in the hospital
update p
	set p.in_hospital=1
	from #fource_LocalPatientClinicalCourse p
		inner join #fource_admissions a
			on a.patient_num=p.patient_num 
				and a.admission_date>=dateadd(dd,-days_since_admission,p.calendar_date)
				and a.admission_date<=p.calendar_date
				and a.discharge_date>=p.calendar_date
-- Flag the days when the patient was in the ICU, making sure the patient was also in the hospital on those days
if exists (select * from #fource_config where icu_data_available=1)
begin
	update p
		set p.in_icu=p.in_hospital
		from #fource_LocalPatientClinicalCourse p
			inner join #fource_icu i
				on i.patient_num=p.patient_num 
					and i.start_date>=dateadd(dd,-days_since_admission,p.calendar_date)
					and i.start_date<=p.calendar_date
					and i.end_date>=p.calendar_date
end

--------------------------------------------------------------------------------
-- LocalPatientSummary: Dates, outcomes, age, and sex
--------------------------------------------------------------------------------
create table #fource_LocalPatientSummary (
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
)
alter table #fource_LocalPatientSummary add primary key (cohort, patient_num, siteid)
-- Get the admission, severe, and death dates; and age and sex.
insert into #fource_LocalPatientSummary
	select '', c.cohort, c.patient_num, c.admission_date,
		c.source_data_updated_date,
		datediff(dd,c.admission_date,c.source_data_updated_date) days_since_admission,
		'1/1/1900' last_discharge_date,
		0 still_in_hospital,
		isnull(c.severe_date,'1/1/1900') severe_date,
		c.severe, 
		'1/1/1900' icu_date,
		(case when x.icu_data_available=0 then -999 else 0 end) in_icu,
		isnull(c.death_date,'1/1/1900') death_date,
		(case when x.death_data_available=0 then -999 when c.death_date is not null then 1 else 0 end) dead,
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
		isnull(substring(m.code,13,99),'other')
	from #fource_config x
		cross join #fource_cohort_patients c
		left outer join crc.patient_dimension p
			on p.patient_num=c.patient_num
		left outer join #fource_code_map m
			on p.sex_cd = m.local_code
				and m.code in ('sex_patient:male','sex_patient:female')
-- Update sex if sex stored in observation_fact table
update s
	set s.sex = (case when s.sex='other' then p.sex when s.sex<>p.sex then 'other' else s.sex end)
	from #fource_LocalPatientSummary s
		inner join (
			select patient_num, (case when male=1 then 'male' else 'female' end) sex
			from (
				select patient_num,
					max(case when m.code='sex_fact:male' then 1 else 0 end) male,
					max(case when m.code='sex_fact:female' then 1 else 0 end) female
				from crc.observation_fact f with (nolock)
					inner join #fource_code_map m
						on f.concept_cd=m.local_code
							and m.code in ('sex_fact:male','sex_fact:female')
				group by patient_num
			) t
			where male+female=1
		) p on s.patient_num = p.patient_num
-- Get the last discharge date and whether the patient is still in the hospital as of the source_data_updated_date.
update s
	set s.last_discharge_date = (case when t.last_discharge_date>s.source_data_updated_date then '1/1/1900' else t.last_discharge_date end),
		s.still_in_hospital = (case when t.last_discharge_date>s.source_data_updated_date then 1 else 0 end)
	from #fource_LocalPatientSummary s
		inner join (
			select p.cohort, p.patient_num, max(a.discharge_date) last_discharge_date
			from #fource_LocalPatientSummary p
				inner join #fource_admissions a
					on a.patient_num=p.patient_num 
						and a.admission_date>=p.admission_date
			group by p.cohort, p.patient_num
		) t on s.cohort=t.cohort and s.patient_num=t.patient_num
-- Get earliest ICU date for patients who were in the ICU.
if exists (select * from #fource_config where icu_data_available=1)
begin
	update s
		set s.icu_date = t.icu_date,
			s.icu = 1
		from #fource_LocalPatientSummary s
			inner join (
				select cohort, patient_num, min(calendar_date) icu_date
					from #fource_LocalPatientClinicalCourse
					where in_icu=1
					group by cohort, patient_num
			) t on s.cohort=t.cohort and s.patient_num=t.patient_num
end


--------------------------------------------------------------------------------
-- LocalPatientObservations: Diagnoses, procedures, medications, and labs
--------------------------------------------------------------------------------
create table #fource_LocalPatientObservations (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	patient_num int not null,
	days_since_admission int not null,
	concept_type varchar(50) not null,
	concept_code varchar(50) not null,
	value numeric(18,5) not null
)
alter table #fource_LocalPatientObservations add primary key (cohort, patient_num, days_since_admission, concept_type, concept_code, siteid)
insert into #fource_LocalPatientObservations
	select '', cohort, patient_num, days_since_admission, concept_type, concept_code, value
	from #fource_observations

--------------------------------------------------------------------------------
-- LocalPatientRace: local and 4CE race code(s) for each patient
--------------------------------------------------------------------------------
create table #fource_LocalPatientRace (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	patient_num int not null,
	race_local_code varchar(500) not null,
	race_4ce varchar(100) not null
)
alter table #fource_LocalPatientRace add primary key (cohort, patient_num, race_local_code, siteid)
if exists (select * from #fource_config where race_data_available=1)
begin
	insert into #fource_LocalPatientRace
		select distinct '', cohort, patient_num, race_local_code, race_4ce
		from (
			-- Race from the patient_dimension table
			select c.cohort, c.patient_num, m.local_code race_local_code, substring(m.code,14,999) race_4ce
				from #fource_cohort_patients c
					inner join crc.patient_dimension p
						on p.patient_num=c.patient_num
					inner join #fource_code_map m
						on p.race_cd = m.local_code
							and m.code like 'race_patient:%'
			union all
			-- Race from the observation_fact table
			select c.cohort, c.patient_num, m.local_code race_local_code, substring(m.code,11,999) race_4ce
				from #fource_cohort_patients c
					inner join crc.observation_fact p with (nolock)
						on p.patient_num=c.patient_num
					inner join #fource_code_map m
						on p.concept_cd = m.local_code
							and m.code like 'race_fact:%'
		) t
end



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
create table #fource_LocalCohorts (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	include_in_phase1 int not null,
	include_in_phase2 int not null,
	source_data_updated_date date not null,
	earliest_adm_date date not null,
	latest_adm_date date not null
)
alter table #fource_LocalCohorts add primary key (cohort, siteid)
insert into #fource_LocalCohorts
	select '', cohort, include_in_phase1, include_in_phase2, source_data_updated_date, earliest_adm_date, latest_adm_date 
	from #fource_cohort_config

--------------------------------------------------------------------------------
-- LocalDailyCounts
--------------------------------------------------------------------------------
create table #fource_LocalDailyCounts (
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
)
alter table #fource_LocalDailyCounts add primary key (cohort, calendar_date, siteid)
-- Get daily counts, except for ICU
insert into #fource_LocalDailyCounts
	select '', cohort, calendar_date, 
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
	from #fource_config x
		cross join #fource_LocalPatientClinicalCourse c
	group by cohort, calendar_date, icu_data_available, death_data_available
-- Update daily counts based on the first time patients were in the ICU
if exists (select * from #fource_config where icu_data_available=1)
begin
	update c
		set cumulative_pts_icu = (
				select count(*)
				from #fource_LocalPatientSummary a
				where a.cohort=c.cohort and a.icu_date<=c.calendar_date and a.icu_date>'1/1/1900'
			),
			cumulative_pts_severe_icu = (
				select count(*)
				from #fource_LocalPatientSummary a
				where a.cohort=c.cohort and a.icu_date<=c.calendar_date and a.icu_date>'1/1/1900' and a.severe=1
			)
		from #fource_LocalDailyCounts c
end

--------------------------------------------------------------------------------
-- LocalClinicalCourse
--------------------------------------------------------------------------------
create table #fource_LocalClinicalCourse (
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
)
alter table #fource_LocalClinicalCourse add primary key (cohort, days_since_admission, siteid)
insert into #fource_LocalClinicalCourse
	select '', c.cohort, c.days_since_admission, 
		sum(c.in_hospital), 
		(case when x.icu_data_available=0 then -999 else sum(c.in_icu) end), 
		(case when x.death_data_available=0 then -999 else sum(c.dead) end), 
		sum(c.severe),
		sum(c.in_hospital*p.severe), 
		(case when x.icu_data_available=0 then -999 else sum(c.in_icu*p.severe) end), 
		(case when x.death_data_available=0 then -999 else sum(c.dead*p.severe) end) 
	from #fource_config x
		cross join #fource_LocalPatientClinicalCourse c
		inner join #fource_cohort_patients p
			on c.cohort=p.cohort and c.patient_num=p.patient_num
	group by c.cohort, c.days_since_admission, icu_data_available, death_data_available

--------------------------------------------------------------------------------
-- LocalAgeSex
--------------------------------------------------------------------------------
create table #fource_LocalAgeSex (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	age_group varchar(20) not null,
	mean_age numeric(18,10) not null,
	sex varchar(10) not null,
	pts_all int not null,
	pts_ever_severe int not null
)
alter table #fource_LocalAgeSex add primary key (cohort, age_group, sex, siteid)
insert into #fource_LocalAgeSex
	select '', cohort, age_group, isnull(avg(cast(nullif(age,-999) as numeric(18,10))),-999), sex, count(*), sum(severe)
		from #fource_LocalPatientSummary
		group by cohort, age_group, sex
	union all
	select '', cohort, 'all', isnull(avg(cast(nullif(age,-999) as numeric(18,10))),-999), sex, count(*), sum(severe)
		from #fource_LocalPatientSummary
		group by cohort, sex
	union all
	select '', cohort, age_group, isnull(avg(cast(nullif(age,-999) as numeric(18,10))),-999), 'all', count(*), sum(severe)
		from #fource_LocalPatientSummary
		group by cohort, age_group
	union all
	select '', cohort, 'all', isnull(avg(cast(nullif(age,-999) as numeric(18,10))),-999), 'all', count(*), sum(severe)
		from #fource_LocalPatientSummary
		group by cohort

--------------------------------------------------------------------------------
-- LocalLabs
--------------------------------------------------------------------------------
create table #fource_LocalLabs (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	loinc varchar(20) not null,
	days_since_admission int not null,
	pts_all int,
	mean_value_all numeric(18,5),
	stdev_value_all numeric(18,5),
	mean_log_value_all numeric(18,10),
	stdev_log_value_all numeric(18,10),
	pts_ever_severe int,
	mean_value_ever_severe numeric(18,5),
	stdev_value_ever_severe numeric(18,5),
	mean_log_value_ever_severe numeric(18,10),
	stdev_log_value_ever_severe numeric(18,10),
	pts_never_severe int,
	mean_value_never_severe numeric(18,5),
	stdev_value_never_severe numeric(18,5),
	mean_log_value_never_severe numeric(18,10),
	stdev_log_value_never_severe numeric(18,10)
)
alter table #fource_LocalLabs add primary key (cohort, loinc, days_since_admission, siteid)
insert into #fource_LocalLabs
	select '' siteid, cohort, concept_code, days_since_admission,
		count(*), 
		avg(value), 
		isnull(stdev(value),0),
		avg(logvalue), 
		isnull(stdev(logvalue),0),
		sum(severe), 
		(case when sum(severe)=0 then -999 else avg(case when severe=1 then value else null end) end), 
		(case when sum(severe)=0 then -999 else isnull(stdev(case when severe=1 then value else null end),0) end),
		(case when sum(severe)=0 then -999 else avg(case when severe=1 then logvalue else null end) end), 
		(case when sum(severe)=0 then -999 else isnull(stdev(case when severe=1 then logvalue else null end),0) end),
		sum(1-severe), 
		(case when sum(1-severe)=0 then -999 else avg(case when severe=0 then value else null end) end), 
		(case when sum(1-severe)=0 then -999 else isnull(stdev(case when severe=0 then value else null end),0) end),
		(case when sum(1-severe)=0 then -999 else avg(case when severe=0 then logvalue else null end) end), 
		(case when sum(1-severe)=0 then -999 else isnull(stdev(case when severe=0 then logvalue else null end),0) end)
	from #fource_observations
	where concept_type='LAB-LOINC' and days_since_admission>=0
	group by cohort, concept_code, days_since_admission

--------------------------------------------------------------------------------
-- LocalDiagProcMed
--------------------------------------------------------------------------------
create table #fource_LocalDiagProcMed (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	concept_type varchar(50) not null,
	concept_code varchar(50) not null,
	pts_all_before_adm int,	-- an observation occurred from day -365 to -15 relative to the admission date
	pts_all_since_adm int, -- an observation occurred on day >=0
	pts_all_dayN14toN1 int, -- an observation occurred from day -14 to -1
	pts_all_day0to29 int, -- an observation occurred from day 0 to 29
	pts_all_day30to89 int, -- an observation occurred from day 30 to 89
	pts_all_day30plus int, -- an observation occurred on day >=30
	pts_all_day90plus int, -- an observation occurred on day >=90
	pts_all_1st_day0to29 int, -- the first observation is day 0 to 29 (no observations from day -365 to -1)
	pts_all_1st_day30plus int, -- the first observation is day >=30 (no observations from day -365 to 29)
	pts_all_1st_day90plus int, -- the first observation is day >=90 (no observations from day -365 to 89)
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
)
alter table #fource_LocalDiagProcMed add primary key (cohort, concept_type, concept_code, siteid)
insert into #fource_LocalDiagProcMed
	select '' siteid, cohort, concept_type, concept_code,
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
			(case when concept_type in ('DIAG-ICD9','DIAG-ICD10') then left(concept_code,3) else concept_code end) concept_code,
			max(case when days_since_admission between -365 and -15 then 1 else 0 end) before_adm,
			max(case when days_since_admission between -14 and -1 then 1 else 0 end) dayN14toN1,
			max(case when days_since_admission >= 0 then 1 else 0 end) since_adm,
			max(case when days_since_admission between 0 and 29 then 1 else 0 end) day0to29,
			max(case when days_since_admission between 30 and 89 then 1 else 0 end) day30to89,
			max(case when days_since_admission >= 30 then 1 else 0 end) day30plus,
			max(case when days_since_admission >= 90 then 1 else 0 end) day90plus,
			min(case when days_since_admission >= 0 then days_since_admission else null end) first_day_since_adm,
			min(days_since_admission) first_day
		from #fource_observations
		where concept_type in ('DIAG-ICD9','DIAG-ICD10','MED-CLASS','PROC-GROUP','COVID-TEST','SEVERE-LAB','SEVERE-DIAG')
		group by cohort, patient_num, severe, concept_type, 
			(case when concept_type in ('DIAG-ICD9','DIAG-ICD10') then left(concept_code,3) else concept_code end)
	) t
	group by cohort, concept_type, concept_code

--------------------------------------------------------------------------------
-- LocalRaceByLocalCode
--------------------------------------------------------------------------------
create table #fource_LocalRaceByLocalCode (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	race_local_code varchar(500) not null,
	race_4ce varchar(100) not null,
	pts_all int not null,
	pts_ever_severe int not null
)
alter table #fource_LocalRaceByLocalCode add primary key (cohort, race_local_code, siteid)
insert into #fource_LocalRaceByLocalCode
	select '', r.cohort, r.race_local_code, r.race_4ce, count(*), sum(p.severe)
	from #fource_LocalPatientRace r
		inner join #fource_cohort_patients p
			on r.cohort=p.cohort and r.patient_num=p.patient_num
	group by r.cohort, r.race_local_code, r.race_4ce

--------------------------------------------------------------------------------
-- LocalRaceBy4CECode
--------------------------------------------------------------------------------
create table #fource_LocalRaceBy4CECode (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	race_4ce varchar(100) not null,
	pts_all int not null,
	pts_ever_severe int not null
)
alter table #fource_LocalRaceBy4CECode add primary key (cohort, race_4ce, siteid)
insert into #fource_LocalRaceBy4CECode
	select '', r.cohort, r.race_4ce, count(*), sum(p.severe)
	from #fource_LocalPatientRace r
		inner join #fource_cohort_patients p
			on r.cohort=p.cohort and r.patient_num=p.patient_num
	group by r.cohort, r.race_4ce



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
--------------------------------------------------------------------------------
create table #fource_Cohorts (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	source_data_updated_date date not null,
	earliest_adm_date date not null,
	latest_adm_date date not null
)
alter table #fource_Cohorts add primary key (cohort, siteid)
insert into #fource_Cohorts
	select '', cohort, source_data_updated_date, earliest_adm_date, latest_adm_date 
	from #fource_cohort_config
	where include_in_phase1=1

--------------------------------------------------------------------------------
-- DailyCounts
--------------------------------------------------------------------------------
create table #fource_DailyCounts (
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
)
alter table #fource_DailyCounts add primary key (cohort, calendar_date, siteid)
insert into #fource_DailyCounts 
	select *
	from #fource_LocalDailyCounts
	where cohort in (select cohort from #fource_cohort_config where include_in_phase1=1)

--------------------------------------------------------------------------------
-- ClinicalCourse
--------------------------------------------------------------------------------
create table #fource_ClinicalCourse (
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
)
alter table #fource_ClinicalCourse add primary key (cohort, days_since_admission)
insert into #fource_ClinicalCourse 
	select * 
	from #fource_LocalClinicalCourse
	where cohort in (select cohort from #fource_cohort_config where include_in_phase1=1)

--------------------------------------------------------------------------------
-- AgeSex
--------------------------------------------------------------------------------
create table #fource_AgeSex (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	age_group varchar(20) not null,
	mean_age numeric(18,10) not null,
	sex varchar(10) not null,
	pts_all int not null,
	pts_ever_severe int not null
)
alter table #fource_AgeSex add primary key (cohort, age_group, sex, siteid)
insert into #fource_AgeSex 
	select * 
	from #fource_LocalAgeSex
	where cohort in (select cohort from #fource_cohort_config where include_in_phase1=1)

--------------------------------------------------------------------------------
-- Labs
--------------------------------------------------------------------------------
create table #fource_Labs (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	loinc varchar(20) not null,
	days_since_admission int not null,
	pts_all int,
	mean_value_all numeric(18,5),
	stdev_value_all numeric(18,5),
	mean_log_value_all numeric(18,10),
	stdev_log_value_all numeric(18,10),
	pts_ever_severe int,
	mean_value_ever_severe numeric(18,5),
	stdev_value_ever_severe numeric(18,5),
	mean_log_value_ever_severe numeric(18,10),
	stdev_log_value_ever_severe numeric(18,10),
	pts_never_severe int,
	mean_value_never_severe numeric(18,5),
	stdev_value_never_severe numeric(18,5),
	mean_log_value_never_severe numeric(18,10),
	stdev_log_value_never_severe numeric(18,10)
)
alter table #fource_Labs add primary key (cohort, loinc, days_since_admission, siteid)
insert into #fource_Labs 
	select * 
	from #fource_LocalLabs
	where cohort in (select cohort from #fource_cohort_config where include_in_phase1=1)
	
--------------------------------------------------------------------------------
-- DiagProcMed
--------------------------------------------------------------------------------
create table #fource_DiagProcMed (
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
	pts_ever_severe_1st_day90plus int,
)
alter table #fource_DiagProcMed add primary key (cohort, concept_type, concept_code, siteid)
insert into #fource_DiagProcMed 
	select * 
	from #fource_LocalDiagProcMed
	where cohort in (select cohort from #fource_cohort_config where include_in_phase1=1)

--------------------------------------------------------------------------------
-- RaceByLocalCode
--------------------------------------------------------------------------------
create table #fource_RaceByLocalCode (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	race_local_code varchar(500) not null,
	race_4ce varchar(100) not null,
	pts_all int not null,
	pts_ever_severe int not null
)
alter table #fource_RaceByLocalCode add primary key (cohort, race_local_code, siteid)
insert into #fource_RaceByLocalCode 
	select * 
	from #fource_LocalRaceByLocalCode
	where cohort in (select cohort from #fource_cohort_config where include_in_phase1=1)

--------------------------------------------------------------------------------
-- RaceBy4CECode
--------------------------------------------------------------------------------
create table #fource_RaceBy4CECode (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	race_4ce varchar(100) not null,
	pts_all int not null,
	pts_ever_severe int not null
)
alter table #fource_RaceBy4CECode add primary key (cohort, race_4ce, siteid)
insert into #fource_RaceBy4CECode 
	select * 
	from #fource_LocalRaceBy4CECode
	where cohort in (select cohort from #fource_cohort_config where include_in_phase1=1)

--------------------------------------------------------------------------------
-- LabCodes
--------------------------------------------------------------------------------
create table #fource_LabCodes (
	siteid varchar(50) not null,
	fource_loinc varchar(20) not null, 
	fource_lab_units varchar(20) not null, 
	fource_lab_name varchar(100) not null,
	scale_factor float not null, 
	local_lab_code varchar(50) not null, 
	local_lab_units varchar(20) not null, 
	local_lab_name varchar(500) not null,
	notes varchar(1000)
)
alter table #fource_LabCodes add primary key (fource_loinc, local_lab_code, local_lab_units, siteid)
insert into #fource_LabCodes
	select '', fource_loinc, fource_lab_units, fource_lab_name, scale_factor, replace(local_lab_code,',',';'), replace(local_lab_units,',',';'), replace(local_lab_name,',',';'), replace(notes,',',';')
	from #fource_lab_map_report



--******************************************************************************
--******************************************************************************
--*** Obfuscate the shared Phase 1 files as needed (optional)
--******************************************************************************
--******************************************************************************


--------------------------------------------------------------------------------
-- Blur counts by adding a small random number.
--------------------------------------------------------------------------------
if exists (select * from #fource_config where obfuscation_blur > 0)
begin
	declare @obfuscation_blur int
	select @obfuscation_blur = obfuscation_blur from #fource_config
	update #fource_DailyCounts
		set cumulative_pts_all = cumulative_pts_all + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			cumulative_pts_icu = cumulative_pts_icu + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			cumulative_pts_dead = cumulative_pts_dead + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			cumulative_pts_severe = cumulative_pts_severe + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			cumulative_pts_severe_icu = cumulative_pts_severe_icu + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			cumulative_pts_severe_dead = cumulative_pts_severe_dead + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_in_hosp_on_this_date = pts_in_hosp_on_this_date + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_in_icu_on_this_date = pts_in_icu_on_this_date + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_severe_in_hosp_on_date = pts_severe_in_hosp_on_date + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_severe_in_icu_on_date = pts_severe_in_icu_on_date + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur
	update #fource_ClinicalCourse
		set pts_all_in_hosp = pts_all_in_hosp + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_all_in_icu = pts_all_in_icu + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_all_dead = pts_all_dead + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_severe_by_this_day = pts_severe_by_this_day + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_in_hosp = pts_ever_severe_in_hosp + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_in_icu = pts_ever_severe_in_icu + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_dead = pts_ever_severe_dead + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur
	update #fource_AgeSex
		set pts_all = pts_all + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe = pts_ever_severe + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur
	update #fource_Labs
		set pts_all = pts_all + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe = pts_ever_severe + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_never_severe = pts_never_severe + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur
	update #fource_DiagProcMed
		set pts_all_before_adm = pts_all_before_adm + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_all_since_adm = pts_all_since_adm + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_all_dayN14toN1 = pts_all_dayN14toN1 + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_all_day0to29 = pts_all_day0to29 + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_all_day30to89 = pts_all_day30to89 + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_all_day30plus = pts_all_day30plus + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_all_day90plus = pts_all_day90plus + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_all_1st_day0to29 = pts_all_1st_day0to29 + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_all_1st_day30plus = pts_all_1st_day30plus + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_all_1st_day90plus = pts_all_1st_day90plus + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_before_adm = pts_ever_severe_before_adm + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_since_adm = pts_ever_severe_since_adm + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_dayN14toN1 = pts_ever_severe_dayN14toN1 + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_day0to29 = pts_ever_severe_day0to29 + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_day30to89 = pts_ever_severe_day30to89 + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_day30plus = pts_ever_severe_day30plus + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_day90plus = pts_ever_severe_day90plus + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_1st_day0to29 = pts_ever_severe_1st_day0to29 + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_1st_day30plus = pts_ever_severe_1st_day30plus + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe_1st_day90plus = pts_ever_severe_1st_day90plus + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur
	update #fource_RaceByLocalCode
		set pts_all = pts_all + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe = pts_ever_severe + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur
	update #fource_RaceBy4CECode
		set pts_all = pts_all + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur,
			pts_ever_severe = pts_ever_severe + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(@obfuscation_blur*2+1)) - @obfuscation_blur
end

--------------------------------------------------------------------------------
-- Mask small counts with "-99".
--------------------------------------------------------------------------------
if exists (select * from #fource_config where obfuscation_small_count_mask > 0)
begin
	declare @obfuscation_small_count_mask int
	select @obfuscation_small_count_mask = obfuscation_small_count_mask from #fource_config
	update #fource_DailyCounts
		set cumulative_pts_all = (case when cumulative_pts_all<@obfuscation_small_count_mask then -99 else cumulative_pts_all end),
			cumulative_pts_icu = (case when cumulative_pts_icu=-999 then -999 when cumulative_pts_icu<@obfuscation_small_count_mask then -99 else cumulative_pts_icu end),
			cumulative_pts_dead = (case when cumulative_pts_dead=-999 then -999 when cumulative_pts_dead<@obfuscation_small_count_mask then -99 else cumulative_pts_dead end),
			cumulative_pts_severe = (case when cumulative_pts_severe<@obfuscation_small_count_mask then -99 else cumulative_pts_severe end),
			cumulative_pts_severe_icu = (case when cumulative_pts_severe_icu=-999 then -999 when cumulative_pts_severe_icu<@obfuscation_small_count_mask then -99 else cumulative_pts_severe_icu end),
			cumulative_pts_severe_dead = (case when cumulative_pts_severe_dead=-999 then -999 when cumulative_pts_severe_dead<@obfuscation_small_count_mask then -99 else cumulative_pts_severe_dead end),
			pts_in_hosp_on_this_date = (case when pts_in_hosp_on_this_date<@obfuscation_small_count_mask then -99 else pts_in_hosp_on_this_date end),
			pts_in_icu_on_this_date = (case when pts_in_icu_on_this_date=-999 then -999 when pts_in_icu_on_this_date<@obfuscation_small_count_mask then -99 else pts_in_icu_on_this_date end),
			pts_severe_in_hosp_on_date = (case when pts_severe_in_hosp_on_date<@obfuscation_small_count_mask then -99 else pts_severe_in_hosp_on_date end),
			pts_severe_in_icu_on_date = (case when pts_severe_in_icu_on_date=-999 then -999 when pts_severe_in_icu_on_date<@obfuscation_small_count_mask then -99 else pts_severe_in_icu_on_date end)
	update #fource_ClinicalCourse
		set pts_all_in_hosp = (case when pts_all_in_hosp<@obfuscation_small_count_mask then -99 else pts_all_in_hosp end),
			pts_all_in_icu = (case when pts_all_in_icu=-999 then -999 when pts_all_in_icu<@obfuscation_small_count_mask then -99 else pts_all_in_icu end),
			pts_all_dead = (case when pts_all_dead=-999 then -999 when pts_all_dead<@obfuscation_small_count_mask then -99 else pts_all_dead end),
			pts_severe_by_this_day = (case when pts_severe_by_this_day<@obfuscation_small_count_mask then -99 else pts_severe_by_this_day end),
			pts_ever_severe_in_hosp = (case when pts_ever_severe_in_hosp<@obfuscation_small_count_mask then -99 else pts_ever_severe_in_hosp end),
			pts_ever_severe_in_icu = (case when pts_ever_severe_in_icu=-999 then -999 when pts_ever_severe_in_icu<@obfuscation_small_count_mask then -99 else pts_ever_severe_in_icu end),
			pts_ever_severe_dead = (case when pts_ever_severe_dead=-999 then -999 when pts_ever_severe_dead<@obfuscation_small_count_mask then -99 else pts_ever_severe_dead end)
	update #fource_AgeSex
		set pts_all = (case when pts_all<@obfuscation_small_count_mask then -99 else pts_all end),
			pts_ever_severe = (case when pts_ever_severe<@obfuscation_small_count_mask then -99 else pts_ever_severe end)
	update #fource_Labs
		set pts_all=-99, mean_value_all=-99, stdev_value_all=-99, mean_log_value_all=-99, stdev_log_value_all=-99
		where pts_all<@obfuscation_small_count_mask
	update #fource_Labs -- Need to mask both ever_severe and never_severe if either of them are below the small count threshold, since all=ever+never
		set pts_ever_severe=-99, mean_value_ever_severe=-99, stdev_value_ever_severe=-99, mean_log_value_ever_severe=-99, stdev_log_value_ever_severe=-99,
			pts_never_severe=-99, mean_value_never_severe=-99, stdev_value_never_severe=-99, mean_log_value_never_severe=-99, stdev_log_value_never_severe=-99
		where (pts_ever_severe<@obfuscation_small_count_mask) or (pts_never_severe<@obfuscation_small_count_mask)
	update #fource_DiagProcMed
		set pts_all_before_adm = (case when pts_all_before_adm<@obfuscation_small_count_mask then -99 else pts_all_before_adm end),
			pts_all_since_adm = (case when pts_all_since_adm<@obfuscation_small_count_mask then -99 else pts_all_since_adm end),
			pts_all_dayN14toN1 = (case when pts_all_dayN14toN1<@obfuscation_small_count_mask then -99 else pts_all_dayN14toN1 end),
			pts_all_day0to29 = (case when pts_all_day0to29<@obfuscation_small_count_mask then -99 else pts_all_day0to29 end),
			pts_all_day30to89 = (case when pts_all_day30to89<@obfuscation_small_count_mask then -99 else pts_all_day30to89 end),
			pts_all_day30plus = (case when pts_all_day30plus<@obfuscation_small_count_mask then -99 else pts_all_day30plus end),
			pts_all_day90plus = (case when pts_all_day90plus<@obfuscation_small_count_mask then -99 else pts_all_day90plus end),
			pts_all_1st_day0to29 = (case when pts_all_1st_day0to29<@obfuscation_small_count_mask then -99 else pts_all_1st_day0to29 end),
			pts_all_1st_day30plus = (case when pts_all_1st_day30plus<@obfuscation_small_count_mask then -99 else pts_all_1st_day30plus end),
			pts_all_1st_day90plus = (case when pts_all_1st_day90plus<@obfuscation_small_count_mask then -99 else pts_all_1st_day90plus end),
			pts_ever_severe_before_adm = (case when pts_ever_severe_before_adm<@obfuscation_small_count_mask then -99 else pts_ever_severe_before_adm end),
			pts_ever_severe_since_adm = (case when pts_ever_severe_since_adm<@obfuscation_small_count_mask then -99 else pts_ever_severe_since_adm end),
			pts_ever_severe_dayN14toN1 = (case when pts_ever_severe_dayN14toN1<@obfuscation_small_count_mask then -99 else pts_ever_severe_dayN14toN1 end),
			pts_ever_severe_day0to29 = (case when pts_ever_severe_day0to29<@obfuscation_small_count_mask then -99 else pts_ever_severe_day0to29 end),
			pts_ever_severe_day30to89 = (case when pts_ever_severe_day30to89<@obfuscation_small_count_mask then -99 else pts_ever_severe_day30to89 end),
			pts_ever_severe_day30plus = (case when pts_ever_severe_day30plus<@obfuscation_small_count_mask then -99 else pts_ever_severe_day30plus end),
			pts_ever_severe_day90plus = (case when pts_ever_severe_day90plus<@obfuscation_small_count_mask then -99 else pts_ever_severe_day90plus end),
			pts_ever_severe_1st_day0to29 = (case when pts_ever_severe_1st_day0to29<@obfuscation_small_count_mask then -99 else pts_ever_severe_1st_day0to29 end),
			pts_ever_severe_1st_day30plus = (case when pts_ever_severe_1st_day30plus<@obfuscation_small_count_mask then -99 else pts_ever_severe_1st_day30plus end),
			pts_ever_severe_1st_day90plus = (case when pts_ever_severe_1st_day90plus<@obfuscation_small_count_mask then -99 else pts_ever_severe_1st_day90plus end)
	update #fource_RaceByLocalCode
		set pts_all = (case when pts_all<@obfuscation_small_count_mask then -99 else pts_all end),
			pts_ever_severe = (case when pts_ever_severe<@obfuscation_small_count_mask then -99 else pts_ever_severe end)
	update #fource_RaceBy4CECode
		set pts_all = (case when pts_all<@obfuscation_small_count_mask then -99 else pts_all end),
			pts_ever_severe = (case when pts_ever_severe<@obfuscation_small_count_mask then -99 else pts_ever_severe end)
end

--------------------------------------------------------------------------------
-- To protect obfuscated age and sex breakdowns, set combinations and 
--   the total count to -999.
--------------------------------------------------------------------------------
if exists (select * from #fource_config where obfuscation_agesex = 1)
begin
	update #fource_AgeSex
		set pts_all = -999, pts_ever_severe = -999, mean_age = -999
		where (age_group<>'all') and (sex<>'all')
end

--------------------------------------------------------------------------------
-- Delete small counts.
--------------------------------------------------------------------------------
if exists (select * from #fource_config where obfuscation_small_count_delete = 1)
begin
	declare @obfuscation_small_count_delete int
	select @obfuscation_small_count_delete = obfuscation_small_count_mask from #fource_config
	delete from #fource_DailyCounts where cumulative_pts_all<@obfuscation_small_count_delete
	delete from #fource_ClinicalCourse where pts_all_in_hosp<@obfuscation_small_count_delete and pts_all_dead<@obfuscation_small_count_delete and pts_severe_by_this_day<@obfuscation_small_count_delete
	delete from #fource_Labs where pts_all<@obfuscation_small_count_delete
	delete from #fource_DiagProcMed 
		where pts_all_before_adm<@obfuscation_small_count_delete 
			and pts_all_since_adm<@obfuscation_small_count_delete 
			and pts_all_dayN14toN1<@obfuscation_small_count_delete
	--Do not delete small count rows from Age, Sex, and Race tables.
	--We want to know the rows in the tables, even if the counts are masked.
	--delete from #fource_AgeSex where pts_all<@obfuscation_small_count_delete
	--delete from #fource_RaceByLocalCode where pts_all<@obfuscation_small_count_delete
	--delete from #fource_RaceBy4CECode where pts_all<@obfuscation_small_count_delete
end



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
delete from #fource_LocalPatientClinicalCourse where cohort in (select cohort from #fource_cohort_config where include_in_phase2=0)
delete from #fource_LocalPatientSummary where cohort in (select cohort from #fource_cohort_config where include_in_phase2=0)
delete from #fource_LocalPatientObservations where cohort in (select cohort from #fource_cohort_config where include_in_phase2=0)
delete from #fource_LocalPatientRace where cohort in (select cohort from #fource_cohort_config where include_in_phase2=0)

--------------------------------------------------------------------------------
-- Remove rows where all values are zeros to reduce the size of the files
--------------------------------------------------------------------------------
delete from #fource_LocalPatientClinicalCourse where in_hospital=0 and severe=0 and in_icu=0 and dead=0

--------------------------------------------------------------------------------
-- Replace the patient_num with a random study_num integer Phase2 tables
--------------------------------------------------------------------------------
create table #fource_LocalPatientMapping (
	siteid varchar(50) not null,
	patient_num int not null,
	study_num int not null
)
alter table #fource_LocalPatientMapping add primary key (patient_num, study_num, siteid)
if exists (select * from #fource_config where replace_patient_num = 1)
begin
	insert into #fource_LocalPatientMapping (siteid, patient_num, study_num)
		select '', patient_num, row_number() over (order by newid()) 
		from (
			select distinct patient_num
			from #fource_LocalPatientSummary
		) t
	update t 
		set t.patient_num = m.study_num 
		from #fource_LocalPatientSummary t 
			inner join #fource_LocalPatientMapping m on t.patient_num = m.patient_num
	update t 
		set t.patient_num = m.study_num 
		from #fource_LocalPatientClinicalCourse t 
			inner join #fource_LocalPatientMapping m on t.patient_num = m.patient_num
	update t 
		set t.patient_num = m.study_num 
		from #fource_LocalPatientObservations t 
			inner join #fource_LocalPatientMapping m on t.patient_num = m.patient_num
	update t 
		set t.patient_num = m.study_num 
		from #fource_LocalPatientRace t 
			inner join #fource_LocalPatientMapping m on t.patient_num = m.patient_num
end
else
begin
	insert into #fource_LocalPatientMapping (siteid, patient_num, study_num)
		select distinct '', patient_num, patient_num
		from #fource_LocalPatientSummary
end

--------------------------------------------------------------------------------
-- Set the siteid to a unique value for your institution.
-- * Make sure you are not using another institution's siteid.
-- * The siteid must be no more than 20 letters or numbers.
-- * It must start with a letter.
-- * It cannot have any blank spaces or special characters.
--------------------------------------------------------------------------------
--Phase 2 patient level tables
update #fource_LocalPatientClinicalCourse set siteid = (select siteid from #fource_config)
update #fource_LocalPatientSummary set siteid = (select siteid from #fource_config)
update #fource_LocalPatientObservations set siteid = (select siteid from #fource_config)
update #fource_LocalPatientRace set siteid = (select siteid from #fource_config)
update #fource_LocalPatientMapping set siteid = (select siteid from #fource_config)
--Phase 2 aggregate count tables
update #fource_LocalCohorts set siteid = (select siteid from #fource_config)
update #fource_LocalDailyCounts set siteid = (select siteid from #fource_config)
update #fource_LocalClinicalCourse set siteid = (select siteid from #fource_config)
update #fource_LocalAgeSex set siteid = (select siteid from #fource_config)
update #fource_LocalLabs set siteid = (select siteid from #fource_config)
update #fource_LocalDiagProcMed set siteid = (select siteid from #fource_config)
update #fource_LocalRaceByLocalCode set siteid = (select siteid from #fource_config)
update #fource_LocalRaceBy4CECode set siteid = (select siteid from #fource_config)
--Phase 1 aggregate count tables
update #fource_Cohorts set siteid = (select siteid from #fource_config)
update #fource_DailyCounts set siteid = (select siteid from #fource_config)
update #fource_ClinicalCourse set siteid = (select siteid from #fource_config)
update #fource_AgeSex set siteid = (select siteid from #fource_config)
update #fource_Labs set siteid = (select siteid from #fource_config)
update #fource_DiagProcMed set siteid = (select siteid from #fource_config)
update #fource_RaceByLocalCode set siteid = (select siteid from #fource_config)
update #fource_RaceBy4CECode set siteid = (select siteid from #fource_config)
update #fource_LabCodes set siteid = (select siteid from #fource_config)



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


if exists (select * from #fource_config where output_phase1_as_columns=1)
begin
	--Phase 1 obfuscated aggregate files
	select * from #fource_DailyCounts order by cohort, calendar_date
	select * from #fource_ClinicalCourse order by cohort, days_since_admission
	select * from #fource_AgeSex order by cohort, age_group, sex
	select * from #fource_Labs order by cohort, loinc, days_since_admission
	select * from #fource_DiagProcMed order by cohort, concept_type, concept_code
	select * from #fource_RaceByLocalCode order by cohort, race_local_code
	select * from #fource_RaceBy4CECode order by cohort, race_4ce
	select * from #fource_LabCodes order by fource_loinc, local_lab_code, local_lab_units
end
if exists (select * from #fource_config where output_phase2_as_columns=1)
begin
	--Phase 2 non-obfuscated local aggregate files
	select * from #fource_LocalDailyCounts order by cohort, calendar_date
	select * from #fource_LocalClinicalCourse order by cohort, days_since_admission
	select * from #fource_LocalAgeSex order by cohort, age_group, sex
	select * from #fource_LocalLabs order by cohort, loinc, days_since_admission
	select * from #fource_LocalDiagProcMed order by cohort, concept_type, concept_code
	select * from #fource_LocalRaceByLocalCode order by cohort, race_local_code
	select * from #fource_LocalRaceBy4CECode order by cohort, race_4ce
	--Phase 2 patient-level files
	select * from #fource_LocalPatientClinicalCourse order by cohort, patient_num, days_since_admission
	select * from #fource_LocalPatientSummary order by cohort, patient_num
	select * from #fource_LocalPatientObservations order by cohort, patient_num, days_since_admission, concept_type, concept_code
	select * from #fource_LocalPatientRace order by cohort, patient_num, race_local_code
	select * from #fource_LocalPatientMapping order by patient_num
end



--******************************************************************************
--******************************************************************************
--*** OPTION #2: View the data as csv strings.
--*** Copy and paste to a text file, save it FileName.csv.
--*** Make sure it is not saved as fource_FileName.csv.
--*** Make sure it is not saved as FileName.csv.txt.
--******************************************************************************
--******************************************************************************


-- Generate SQL that concatenates the columns of each table into a csv string
create table #fource_file_csv (
	file_index int,
	file_name varchar(50),
	file_sql nvarchar(max)
)
insert into #fource_file_csv
	select i, file_name,
		'select s '+file_name+'CSV '
		+'from ( '
		+'select 0 z, '''+replace(replace(replace(column_list,'{',''),'}',''),'|',',')+''' s '
		+'union all '
		+'select row_number() over (order by '+order_by+') z, '
		+'cast('
		+replace(
			replace(replace(column_list,'{','convert(varchar(50),'),'}',',23)'), --Convert dates to "YYYY-MM-DD"
			'|',' as varchar(max))+'',''+cast('
			)
		+' as varchar(max)) '
		+'from #fource_'+file_name+' '
		+'union all select 9999999 z, ''''' --Add a blank row to make sure the last line in the file with data ends with a line feed. '
		+') t '
		+'order by z;' s
	from (
		--List the name of each file, the columns used to sort the rows in the file, and the full list of columns in the file.
		--In the column list, place curly brackets "{" and "}" around date columns. This will convert them to YYYY-MM-DD format in the csv strings.
		select 0 i, '' file_name, '' order_by, '' column_list where 1=0
		--Phase 1 obfuscated aggregate files
		union all select 1,'DailyCounts','cohort,calendar_date','siteid|cohort|{calendar_date}|cumulative_pts_all|cumulative_pts_icu|cumulative_pts_dead|cumulative_pts_severe|cumulative_pts_severe_icu|cumulative_pts_severe_dead|pts_in_hosp_on_this_date|pts_in_icu_on_this_date|pts_severe_in_hosp_on_date|pts_severe_in_icu_on_date'
		union all select 2,'ClinicalCourse','cohort,days_since_admission','siteid|cohort|days_since_admission|pts_all_in_hosp|pts_all_in_icu|pts_all_dead|pts_severe_by_this_day|pts_ever_severe_in_hosp|pts_ever_severe_in_icu|pts_ever_severe_dead'
		union all select 3,'AgeSex','cohort,age_group,sex','siteid|cohort|age_group|mean_age|sex|pts_all|pts_ever_severe'
		union all select 4,'Labs','cohort,loinc,days_since_admission','siteid|cohort|loinc|days_since_admission|pts_all|mean_value_all|stdev_value_all|mean_log_value_all|stdev_log_value_all|pts_ever_severe|mean_value_ever_severe|stdev_value_ever_severe|mean_log_value_ever_severe|stdev_log_value_ever_severe|pts_never_severe|mean_value_never_severe|stdev_value_never_severe|mean_log_value_never_severe|stdev_log_value_never_severe'
		union all select 5,'DiagProcMed','cohort,concept_type,concept_code','siteid|cohort|concept_type|concept_code|pts_all_before_adm|pts_all_since_adm|pts_all_dayN14toN1|pts_all_day0to29|pts_all_day30to89|pts_all_day30plus|pts_all_day90plus|pts_all_1st_day0to29|pts_all_1st_day30plus|pts_all_1st_day90plus|pts_ever_severe_before_adm|pts_ever_severe_since_adm|pts_ever_severe_dayN14toN1|pts_ever_severe_day0to29|pts_ever_severe_day30to89|pts_ever_severe_day30plus|pts_ever_severe_day90plus|pts_ever_severe_1st_day0to29|pts_ever_severe_1st_day30plus|pts_ever_severe_1st_day90plus'
		union all select 6,'RaceByLocalCode','cohort,race_local_code','siteid|cohort|race_local_code|race_4ce|pts_all|pts_ever_severe'
		union all select 7,'RaceBy4CECode','cohort,race_4ce','siteid|cohort|race_4ce|pts_all|pts_ever_severe'
		union all select 8,'LabCodes','fource_loinc,local_lab_code,local_lab_units','siteid|fource_loinc|fource_lab_units|fource_lab_name|scale_factor|local_lab_code|local_lab_units|local_lab_name|notes'
		--Phase 2 non-obfuscated local aggregate files
		union all select 9,'LocalDailyCounts','cohort,calendar_date','siteid|cohort|{calendar_date}|cumulative_pts_all|cumulative_pts_icu|cumulative_pts_dead|cumulative_pts_severe|cumulative_pts_severe_icu|cumulative_pts_severe_dead|pts_in_hosp_on_this_date|pts_in_icu_on_this_date|pts_severe_in_hosp_on_date|pts_severe_in_icu_on_date'
		union all select 10,'LocalClinicalCourse','cohort,days_since_admission','siteid|cohort|days_since_admission|pts_all_in_hosp|pts_all_in_icu|pts_all_dead|pts_severe_by_this_day|pts_ever_severe_in_hosp|pts_ever_severe_in_icu|pts_ever_severe_dead'
		union all select 11,'LocalAgeSex','cohort,age_group,sex','siteid|cohort|age_group|mean_age|sex|pts_all|pts_ever_severe'
		union all select 12,'LocalLabs','cohort,loinc,days_since_admission','siteid|cohort|loinc|days_since_admission|pts_all|mean_value_all|stdev_value_all|mean_log_value_all|stdev_log_value_all|pts_ever_severe|mean_value_ever_severe|stdev_value_ever_severe|mean_log_value_ever_severe|stdev_log_value_ever_severe|pts_never_severe|mean_value_never_severe|stdev_value_never_severe|mean_log_value_never_severe|stdev_log_value_never_severe'
		union all select 13,'LocalDiagProcMed','cohort,concept_type,concept_code','siteid|cohort|concept_type|concept_code|pts_all_before_adm|pts_all_since_adm|pts_all_dayN14toN1|pts_all_day0to29|pts_all_day30to89|pts_all_day30plus|pts_all_day90plus|pts_all_1st_day0to29|pts_all_1st_day30plus|pts_all_1st_day90plus|pts_ever_severe_before_adm|pts_ever_severe_since_adm|pts_ever_severe_dayN14toN1|pts_ever_severe_day0to29|pts_ever_severe_day30to89|pts_ever_severe_day30plus|pts_ever_severe_day90plus|pts_ever_severe_1st_day0to29|pts_ever_severe_1st_day30plus|pts_ever_severe_1st_day90plus'
		union all select 14,'LocalRaceByLocalCode','cohort,race_local_code','siteid|cohort|race_local_code|race_4ce|pts_all|pts_ever_severe'
		union all select 15,'LocalRaceBy4CECode','cohort,race_4ce','siteid|cohort|race_4ce|pts_all|pts_ever_severe'
		--Phase 2 patient-level files
		union all select 16,'LocalPatientClinicalCourse','cohort,patient_num,days_since_admission','siteid|cohort|patient_num|days_since_admission|calendar_date|in_hospital|severe|in_icu|dead'
		union all select 17,'LocalPatientSummary','cohort,patient_num','siteid|cohort|patient_num|admission_date|{source_data_updated_date}|days_since_admission|{last_discharge_date}|still_in_hospital|{severe_date}|severe|{icu_date}|icu|{death_date}|dead|age_group|age|sex'
		union all select 18,'LocalPatientObservations','cohort,patient_num,days_since_admission,concept_type,concept_code','siteid|cohort|patient_num|days_since_admission|concept_type|concept_code|value'
		union all select 19,'LocalPatientRace','cohort,patient_num,race_local_code','siteid|cohort|patient_num|race_local_code|race_4ce'
		union all select 20,'LocalPatientMapping','patient_num','siteid|patient_num|study_num'
	) t

-- Run the SQL for the appropriate tables
declare @FileSQL nvarchar(max)
declare @FileIndex int
select @FileIndex=1
while (@FileIndex<=20)
begin
	if exists (select * from #fource_config where (output_phase1_as_csv=1 and @FileIndex<=8) or (output_phase2_as_csv=1 and @FileIndex>=9))
	begin
		select @FileSQL=file_sql
			from #fource_file_csv
				cross apply #fource_config
			where file_index=@FileIndex
				and ((output_phase1_as_csv=1 and file_index<=8) or (output_phase2_as_csv=1 and file_index>=9))
		exec sp_executesql @FileSQL
	end
	select @FileIndex=@FileIndex+1
end

-- Optional: Run the commented code below to generate SQL for previously saved tables, rather than the temp tables.
-- Replace "dbo.fource_" with the prefix you used to save the tables.
-- Copy and paste the SQL strings into a query window and run the queries.
/* 
select file_index, file_name, replace(file_sql,'#fource_','dbo.FourCE_') file_sql
	from #fource_file_csv
	order by file_index
*/


--******************************************************************************
--******************************************************************************
--*** OPTION #3: Save the data as tables.
--*** Make sure everything looks reasonable.
--*** Export the tables to csv files.
--******************************************************************************
--******************************************************************************


if exists (select * from #fource_config where save_phase1_as_columns=1)
begin
	-- Drop existing tables
	declare @SavePhase1AsTablesSQL nvarchar(max)
	select @SavePhase1AsTablesSQL = ''
		--Phase 1 obfuscated aggregate files
		+'if (select object_id('''+save_phase1_as_prefix+'DailyCounts'', ''U'') from #fource_config) is not null drop table '+save_phase1_as_prefix+'DailyCounts;'
		+'if (select object_id('''+save_phase1_as_prefix+'ClinicalCourse'', ''U'') from #fource_config) is not null drop table '+save_phase1_as_prefix+'ClinicalCourse;'
		+'if (select object_id('''+save_phase1_as_prefix+'AgeSex'', ''U'') from #fource_config) is not null drop table '+save_phase1_as_prefix+'AgeSex;'
		+'if (select object_id('''+save_phase1_as_prefix+'Labs'', ''U'') from #fource_config) is not null drop table '+save_phase1_as_prefix+'Labs;'
		+'if (select object_id('''+save_phase1_as_prefix+'DiagProcMed'', ''U'') from #fource_config) is not null  drop table '+save_phase1_as_prefix+'DiagProcMed;'
		+'if (select object_id('''+save_phase1_as_prefix+'RaceByLocalCode'', ''U'') from #fource_config) is not null drop table '+save_phase1_as_prefix+'RaceByLocalCode;'
		+'if (select object_id('''+save_phase1_as_prefix+'RaceBy4CECode'', ''U'') from #fource_config) is not null drop table '+save_phase1_as_prefix+'RaceBy4CECode;'
		+'if (select object_id('''+save_phase1_as_prefix+'LabCodes'', ''U'') from #fource_config) is not null drop table '+save_phase1_as_prefix+'LabCodes;'
		from #fource_config
	exec sp_executesql @SavePhase1AsTablesSQL
	-- Save new tables
	select @SavePhase1AsTablesSQL = ''
		--Phase 1 obfuscated aggregate files
		+'select * into '+save_phase1_as_prefix+'DailyCounts from #fource_DailyCounts;'
		+'select * into '+save_phase1_as_prefix+'ClinicalCourse from #fource_ClinicalCourse;'
		+'select * into '+save_phase1_as_prefix+'AgeSex from #fource_AgeSex;'
		+'select * into '+save_phase1_as_prefix+'Labs from #fource_Labs;'
		+'select * into '+save_phase1_as_prefix+'DiagProcMed from #fource_DiagProcMed;'
		+'select * into '+save_phase1_as_prefix+'RaceByLocalCode from #fource_RaceByLocalCode;'
		+'select * into '+save_phase1_as_prefix+'RaceBy4CECode from #fource_RaceBy4CECode;'
		+'select * into '+save_phase1_as_prefix+'LabCodes from #fource_LabCodes;'
		+'alter table '+save_phase1_as_prefix+'DailyCounts add primary key (cohort, calendar_date, siteid);'
		+'alter table '+save_phase1_as_prefix+'ClinicalCourse add primary key (cohort, days_since_admission, siteid);'
		+'alter table '+save_phase1_as_prefix+'AgeSex add primary key (cohort, age_group, sex, siteid);'
		+'alter table '+save_phase1_as_prefix+'Labs add primary key (cohort, loinc, days_since_admission, siteid);'
		+'alter table '+save_phase1_as_prefix+'DiagProcMed add primary key (cohort, concept_type, concept_code, siteid);'
		+'alter table '+save_phase1_as_prefix+'RaceByLocalCode add primary key (cohort, race_local_code, siteid);'
		+'alter table '+save_phase1_as_prefix+'RaceBy4CECode add primary key (cohort, race_4ce, siteid);'
		+'alter table '+save_phase1_as_prefix+'LabCodes add primary key (fource_loinc, local_lab_code, local_lab_units, siteid);'
		from #fource_config
	exec sp_executesql @SavePhase1AsTablesSQL
end

if exists (select * from #fource_config where save_phase2_as_columns=1)
begin
	-- Drop existing tables
	declare @SavePhase2AsTablesSQL nvarchar(max)
	select @SavePhase2AsTablesSQL = ''
		--Phase 2 non-obfuscated local aggregate files
		+'if (select object_id('''+save_phase2_as_prefix+'LocalDailyCounts'', ''U'') from #fource_config) is not null drop table '+save_phase2_as_prefix+'LocalDailyCounts;'
		+'if (select object_id('''+save_phase2_as_prefix+'LocalClinicalCourse'', ''U'') from #fource_config) is not null drop table '+save_phase2_as_prefix+'LocalClinicalCourse;'
		+'if (select object_id('''+save_phase2_as_prefix+'LocalAgeSex'', ''U'') from #fource_config) is not null drop table '+save_phase2_as_prefix+'LocalAgeSex;'
		+'if (select object_id('''+save_phase2_as_prefix+'LocalLabs'', ''U'') from #fource_config) is not null drop table '+save_phase2_as_prefix+'LocalLabs;'
		+'if (select object_id('''+save_phase2_as_prefix+'LocalDiagProcMed'', ''U'') from #fource_config) is not null  drop table '+save_phase2_as_prefix+'LocalDiagProcMed;'
		+'if (select object_id('''+save_phase2_as_prefix+'LocalRaceByLocalCode'', ''U'') from #fource_config) is not null drop table '+save_phase2_as_prefix+'LocalRaceByLocalCode;'
		+'if (select object_id('''+save_phase2_as_prefix+'LocalRaceBy4CECode'', ''U'') from #fource_config) is not null drop table '+save_phase2_as_prefix+'LocalRaceBy4CECode;'
		--Phase 2 patient-level files
		+'if (select object_id('''+save_phase2_as_prefix+'LocalPatientSummary'', ''U'') from #fource_config) is not null drop table '+save_phase2_as_prefix+'LocalPatientSummary;'
		+'if (select object_id('''+save_phase2_as_prefix+'LocalPatientClinicalCourse'', ''U'') from #fource_config) is not null drop table '+save_phase2_as_prefix+'LocalPatientClinicalCourse;'
		+'if (select object_id('''+save_phase2_as_prefix+'LocalPatientObservations'', ''U'') from #fource_config) is not null drop table '+save_phase2_as_prefix+'LocalPatientObservations;'
		+'if (select object_id('''+save_phase2_as_prefix+'LocalPatientRace'', ''U'') from #fource_config) is not null drop table '+save_phase2_as_prefix+'LocalPatientRace;'
		+'if (select object_id('''+save_phase2_as_prefix+'LocalPatientMapping'', ''U'') from #fource_config) is not null drop table '+save_phase2_as_prefix+'LocalPatientMapping;'
		from #fource_config
	exec sp_executesql @SavePhase2AsTablesSQL
	-- Save new tables
	select @SavePhase2AsTablesSQL = ''
		--Phase 2 non-obfuscated local aggregate files
		+'select * into '+save_phase2_as_prefix+'LocalDailyCounts from #fource_LocalDailyCounts;'
		+'select * into '+save_phase2_as_prefix+'LocalClinicalCourse from #fource_LocalClinicalCourse;'
		+'select * into '+save_phase2_as_prefix+'LocalAgeSex from #fource_LocalAgeSex;'
		+'select * into '+save_phase2_as_prefix+'LocalLabs from #fource_LocalLabs;'
		+'select * into '+save_phase2_as_prefix+'LocalDiagProcMed from #fource_LocalDiagProcMed;'
		+'select * into '+save_phase2_as_prefix+'LocalRaceByLocalCode from #fource_LocalRaceByLocalCode;'
		+'select * into '+save_phase2_as_prefix+'LocalRaceBy4CECode from #fource_LocalRaceBy4CECode;'
		+'alter table '+save_phase2_as_prefix+'LocalDailyCounts add primary key (cohort, calendar_date, siteid);'
		+'alter table '+save_phase2_as_prefix+'LocalClinicalCourse add primary key (cohort, days_since_admission, siteid);'
		+'alter table '+save_phase2_as_prefix+'LocalAgeSex add primary key (cohort, age_group, sex, siteid);'
		+'alter table '+save_phase2_as_prefix+'LocalLabs add primary key (cohort, loinc, days_since_admission, siteid);'
		+'alter table '+save_phase2_as_prefix+'LocalDiagProcMed add primary key (cohort, concept_type, concept_code, siteid);'
		+'alter table '+save_phase2_as_prefix+'LocalRaceByLocalCode add primary key (cohort, race_local_code, siteid);'
		+'alter table '+save_phase2_as_prefix+'LocalRaceBy4CECode add primary key (cohort, race_4ce, siteid);'
		--Phase 2 patient-level files
		+'select * into '+save_phase2_as_prefix+'LocalPatientSummary from #fource_LocalPatientSummary;'
		+'select * into '+save_phase2_as_prefix+'LocalPatientClinicalCourse from #fource_LocalPatientClinicalCourse;'
		+'select * into '+save_phase2_as_prefix+'LocalPatientObservations from #fource_LocalPatientObservations;'
		+'select * into '+save_phase2_as_prefix+'LocalPatientRace from #fource_LocalPatientRace;'
		+'select * into '+save_phase2_as_prefix+'LocalPatientMapping from #fource_LocalPatientMapping;'
		+'alter table '+save_phase2_as_prefix+'LocalPatientClinicalCourse add primary key (cohort, patient_num, days_since_admission, siteid);'
		+'alter table '+save_phase2_as_prefix+'LocalPatientMapping add primary key (patient_num, study_num, siteid);'
		+'alter table '+save_phase2_as_prefix+'LocalPatientObservations add primary key (cohort, patient_num, days_since_admission, concept_type, concept_code, siteid);'
		+'alter table '+save_phase2_as_prefix+'LocalPatientRace add primary key (cohort, patient_num, race_local_code, siteid);'
		+'alter table '+save_phase2_as_prefix+'LocalPatientSummary add primary key (cohort, patient_num, siteid);'
		from #fource_config
	exec sp_executesql @SavePhase2AsTablesSQL
end


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
drop table #fource_config

-- Code mapping tables
drop table #fource_code_map
drop table #fource_med_map
drop table #fource_proc_map
drop table #fource_lab_map
drop table #fource_lab_units_facts
drop table #fource_lab_map_report
-- Admissions, ICU visits, and deaths
drop table #fource_admissions
drop table #fource_icu
drop table #fource_death
-- COVID tests, cohort definitions and patients
drop table #fource_cohort_config
drop table #fource_covid_tests
drop table #fource_first_covid_tests
drop table #fource_date_list
drop table #fource_cohort_patients
-- List of patients and observations mapped to 4CE codes
drop table #fource_patients
drop table #fource_observations
-- Used to create the CSV formatted tables
drop table #fource_file_csv

-- Phase 1 obfuscated aggregate files
drop table #fource_DailyCounts 
drop table #fource_ClinicalCourse 
drop table #fource_AgeSex 
drop table #fource_Labs 
drop table #fource_DiagProcMed 
drop table #fource_RaceByLocalCode 
drop table #fource_RaceBy4CECode 
drop table #fource_LabCodes 
-- Phase 2 non-obfuscated local aggregate files
drop table #fource_LocalDailyCounts 
drop table #fource_LocalClinicalCourse 
drop table #fource_LocalAgeSex 
drop table #fource_LocalLabs 
drop table #fource_LocalDiagProcMed 
drop table #fource_LocalRaceByLocalCode 
drop table #fource_LocalRaceBy4CECode 
-- Phase 2 patient-level files
drop table #fource_LocalPatientSummary 
drop table #fource_LocalPatientClinicalCourse 
drop table #fource_LocalPatientObservations 
drop table #fource_LocalPatientRace 
drop table #fource_LocalPatientMapping 

*/

