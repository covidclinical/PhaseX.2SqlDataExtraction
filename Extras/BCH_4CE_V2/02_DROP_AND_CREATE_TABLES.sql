-- Main configuration table
/*drop table fource_config;

-- Code mapping tables;
drop table fource_code_map;
drop table fource_med_map;
drop table fource_proc_map;
drop table fource_lab_map;
drop table fource_lab_units_facts;
drop table fource_lab_map_report;*/
-- Admissions, ICU visits, and deaths;
drop table fource_admissions;
drop table fource_icu;
drop table fource_death;

-- COVID tests, cohort definitions and patients;
drop table fource_cohort_config;
drop table fource_covid_tests;
drop table fource_first_covid_tests;
drop table fource_date_list;
drop table fource_cohort_patients;
-- List of patients and observations mapped to 4CE codes;
drop table fource_patients;
drop table fource_observations;
-- Used to create the CSV formatted tables;
--drop table fource_file_csv;

drop table fource_LocalCohorts ;
drop table fource_Cohorts;

-- Phase 1 obfuscated aggregate files;
drop table fource_DailyCounts ;
drop table fource_ClinicalCourse ;
drop table fource_AgeSex ;
drop table fource_Labs ;
drop table fource_DiagProcMed ;
drop table fource_RaceByLocalCode ;
drop table fource_RaceBy4CECode ;
drop table fource_LabCodes ;
-- Phase 2 non-obfuscated local aggregate files;
drop table fource_LocalDailyCounts ;
drop table fource_LocalClinicalCourse ;
drop table fource_LocalAgeSex ;
drop table fource_LocalLabs ;
drop table fource_LocalDiagProcMed ;
drop table fource_LocalRaceByLocalCode ;
drop table fource_LocalRaceBy4CECode ;
-- Phase 2 patient-level files;
drop table fource_LocalPatientSummary ;
drop table fource_LocalPatClinicalCourse ;
drop table fource_LocalPatObservations ;
drop table fource_LocalPatientRace ;
drop table fource_LocalPatientMapping ;
drop table stg_fource_misc;        

drop table fource_misc;

create table stg_fource_misc
(
mrn  varchar2(100),
misc_date varchar2(50) );
create table fource_misc (
        patient_num int not null,
        misc_date date not null
);
alter table fource_misc add primary key (patient_num);


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

--------------------------------------------------------------------------------
--drop table fource_code_map;
create table fource_code_map (
	code varchar(50) not null,
	local_code varchar(50) not null
);

alter table fource_code_map add primary key (code, local_code);



--create table fource_icu_location as select cast(department_id as varchar2(50)) location_cd from icus;

create table fource_lab_map (
	fource_loinc varchar(20) not null, 
	fource_lab_units varchar(20) not null, 
	fource_lab_name varchar(100) not null,
	scale_factor float not null, 
	local_lab_code varchar(50) not null, 
	local_lab_units varchar(100) not null, 
	local_lab_name varchar(500) not null
);

alter table fource_lab_map add primary key (fource_loinc, local_lab_code, local_lab_units);

--------------------------------------------------------------------------------
-- Lab mappings report (for debugging lab mappings)
--------------------------------------------------------------------------------
-- Get a list of all the codes and units in the data for 4CE labs since 1/1/2019
create table fource_lab_units_facts (
	fact_code varchar(50) not null,
	fact_units varchar(50),
	num_facts int,
	mean_value numeric(18,5),
	stdev_value numeric(18,5)
); 

--188s
create index fource_lap_map_ndx on fource_lab_map(local_lab_code);

-- Create a table that stores a report about local lab units
--drop table fource_lab_map_report;
create table fource_lab_map_report (
	fource_loinc varchar(20) not null, 
	fource_lab_units varchar(20), 
	fource_lab_name varchar(100),
	scale_factor float, 
	local_lab_code varchar(50) not null, 
	local_lab_units varchar(100) not null, 
	local_lab_name varchar(500),
	num_facts int,
	mean_value numeric(18,5),
	stdev_value numeric(18,5),
	notes varchar(1000)
)
; 
alter table fource_lab_map_report add primary key (fource_loinc, local_lab_code, local_lab_units);
-- Compare the fource_lab_map table to the codes and units in the data


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

--------------------------------------------------------------------------------
-- Multisystem Inflammatory Syndrome in Children (MIS-C) (optional)
-- * Write a custom query to populate this table with the patient_num's of
-- * children who develop MIS-C and their first MIS-C diagnosis date.
--------------------------------------------------------------------------------
--drop table fource_misc;
create table fource_misc (
	patient_num int not null,
	misc_date date not null
);
alter table fource_misc add primary key (patient_num);


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


--------------------------------------------------------------------------------
-- Create a list of dates when patients died.
--------------------------------------------------------------------------------
--drop table fource_death;
create table fource_death (
	patient_num int not null,
	death_date date not null
);

alter table fource_death add primary key (patient_num);


create table fource_first_covid_tests (
	patient_num int not null,
	first_pos_date date,
	first_neg_date date,
	first_U071_date date
);

alter table fource_first_covid_tests add primary key (patient_num); 


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


--------------------------------------------------------------------------------
-- Flag the patients who had severe disease with 30 days of admission.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Add death dates to patients who have died.

create table fource_date_list (
	cohort varchar(50) not null,
	d date not null
);

alter table fource_date_list add primary key (cohort, d);


--------------------------------------------------------------------------------
-- LocalPatientClinicalCourse: Status by number of days since admission
--------------------------------------------------------------------------------

create table FOURCE_LOCALPATCLINICALCOURSE (
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

alter table FOURCE_LOCALPATCLINICALCOURSE add primary key (cohort, patient_num, days_since_admission, siteid);
-- Get the list of dates and flag the ones where the patients were severe or deceased

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

--------------------------------------------------------------------------------
-- FOURCE_LOCALPATOBSERVATIONS: Diagnoses, procedures, medications, and labs
--------------------------------------------------------------------------------

create table FOURCE_LOCALPATOBSERVATIONS (
	siteid varchar(50) not null,
	cohort varchar(50) not null,
	patient_num int not null,
	days_since_admission int not null,
	concept_type varchar(50) not null,
	concept_code varchar(50) not null,
	value numeric(18,5) not null
);
alter table FOURCE_LOCALPATOBSERVATIONS add primary key (cohort, patient_num, days_since_admission, concept_type, concept_code, siteid);

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
); 
alter table fource_LocalLabs add primary key (cohort, loinc, days_since_admission, siteid);


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
);
alter table fource_Labs add primary key (cohort, loinc, days_since_admission, siteid);

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
	local_lab_units varchar(100) not null, 
	local_lab_name varchar(500) not null,
	notes varchar(1000)
);
alter table fource_LabCodes add primary key (fource_loinc, local_lab_code, local_lab_units, siteid);

--------------------------------------------------------------------------
-- Replace the patient_num with a random study_num integer Phase2 tables
-- if replace_patient_num is set to 0 this code won't do anything so you can comment out 
--------------------------------------------------------------------------------
create table fource_LocalPatientMapping (
	siteid varchar(50) not null,
	patient_num int not null,
	study_num int not null
);
alter table fource_LocalPatientMapping add primary key (patient_num, study_num, siteid);



  CREATE TABLE ETL_RUN_LOG 
   (	LOG_ID NUMBER NOT NULL ENABLE, 
	RUN_ID NUMBER NOT NULL ENABLE, 
	LOG_MESSAGE VARCHAR2(4000) NOT NULL ENABLE, 
	LOG_MESSAGE_TYPE VARCHAR2(32) NOT NULL ENABLE, 
	LOG_TIMESTAMP TIMESTAMP (6) NOT NULL ENABLE, 
	LOG_SESSION_ID VARCHAR2(32)
   ) ;
          

CREATE SEQUENCE ETL_LOG_SEQ1 INCREMENT BY 1 START WITH 1 CACHE 20 ORDER;

create or replace PACKAGE           LOG_PKG AS 
		    PROCEDURE log_msg(
		        p_runid IN NUMBER DEFAULT -9,
		        p_msg      IN VARCHAR2,
		        p_msg_type IN VARCHAR2 DEFAULT 'X');

		END LOG_PKG;
/

create or replace PACKAGE BODY           LOG_PKG
		AS
		
		  PROCEDURE log_msg(
		      p_runid IN NUMBER DEFAULT -9,
		      p_msg      IN VARCHAR2,
		      p_msg_type IN VARCHAR2 DEFAULT 'X')
		  AS
		    v_logid NUMBER := 0;
		    PRAGMA AUTONOMOUS_TRANSACTION;
		  BEGIN

		    select ETL_LOG_SEQ1.nextval into v_logid from dual;
		    INSERT INTO ETL_RUN_LOG VALUES
		      (v_logid, p_runid, p_msg, p_msg_type, CURRENT_TIMESTAMP, DBMS_SESSION.unique_session_id
		      );
		    COMMIT;  

		  END;

		END LOG_PKG;
        
        /
        
        


        
        
