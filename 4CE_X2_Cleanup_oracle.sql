-- Main configuration table
drop table fource_config;

-- Code mapping tables;
drop table fource_code_map;
drop table fource_med_map;
drop table fource_proc_map;
drop table fource_lab_map;
drop table fource_lab_units_facts;
drop table fource_lab_map_report;
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
drop table fource_LocalPatientClinicalCourse ;
drop table fource_LocalPatientObservations ;
drop table fource_LocalPatientRace ;
drop table fource_LocalPatientMapping; 
commit;

