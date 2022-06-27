set pagesize 0
set echo off
set feedback off
set term off
set linesize 4000

set heading off
set verify off

set trimspool on
BEGIN
EXECUTE IMMEDIATE 'alter session set nls_date_format="yyyy-mm-dd"';
END;
/

spool DailyCounts-BCH.csv
select s DailyCountsCSV from ( select 0 z, 'siteid,cohort,calendar_date,cumulative_pts_all,cumulative_pts_icu,cumulative_pts_dead,cumulative_pts_severe,cumulative_pts_severe_icu,cumulative_pts_severe_dead,pts_in_hosp_on_this_date,pts_in_icu_on_this_date,pts_severe_in_hosp_on_date,pts_severe_in_icu_on_date' s from dual union all select row_number() over (order by cohort,calendar_date) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || to_char(calendar_date, 'YYYY-MM-DD') || ',' || cast(cumulative_pts_all as varchar2(2000)) || ',' || cast(cumulative_pts_icu as varchar2(2000)) || ',' || cast(cumulative_pts_dead as varchar2(2000)) || ',' || cast(cumulative_pts_severe as varchar2(2000)) || ',' || cast(cumulative_pts_severe_icu as varchar2(2000)) || ',' || cast(cumulative_pts_severe_dead as varchar2(2000)) || ',' || cast(pts_in_hosp_on_this_date as varchar2(2000)) || ',' || cast(pts_in_icu_on_this_date as varchar2(2000)) || ',' || cast(pts_severe_in_hosp_on_date as varchar2(2000)) || ',' || cast(pts_severe_in_icu_on_date as varchar2(2000)) from jaspreetk.fource_DailyCounts --union all select 9999999 z, '' from dual
) t order by z;
spool off


spool ClinicalCourse-BCH.csv
select s ClinicalCourseCSV from ( select 0 z, 'siteid,cohort,days_since_admission,pts_all_in_hosp,pts_all_in_icu,pts_all_dead,pts_severe_by_this_day,pts_ever_severe_in_hosp,pts_ever_severe_in_icu,pts_ever_severe_dead' s from dual union all select row_number() over (order by cohort,days_since_admission) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(days_since_admission as varchar2(2000)) || ',' || cast(pts_all_in_hosp as varchar2(2000)) || ',' || cast(pts_all_in_icu as varchar2(2000)) || ',' || cast(pts_all_dead as varchar2(2000)) || ',' || cast(pts_severe_by_this_day as varchar2(2000)) || ',' || cast(pts_ever_severe_in_hosp as varchar2(2000)) || ',' || cast(pts_ever_severe_in_icu as varchar2(2000)) || ',' || cast(pts_ever_severe_dead as varchar2(2000)) from jaspreetk.fource_ClinicalCourse --union all select 9999999 z, '' from dual
) t order by z;
spool off


spool AgeSex-BCH.csv
select s AgeSexCSV from ( select 0 z, 'siteid,cohort,age_group,mean_age,sex,pts_all,pts_ever_severe' s from dual union all select row_number() over (order by cohort,age_group,sex) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(age_group as varchar2(2000)) || ',' || cast(mean_age as varchar2(2000)) || ',' || cast(sex as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) from jaspreetk.fource_AgeSex
) t order by z;
spool off


spool Labs-BCH.csv
select s LabsCSV from ( select 0 z, 'siteid,cohort,loinc,days_since_admission,pts_all,mean_value_all,stdev_value_all,mean_log_value_all,stdev_log_value_all,pts_ever_severe,mean_value_ever_severe,stdev_value_ever_severe,mean_log_value_ever_severe,stdev_log_value_ever_severe,pts_never_severe,mean_value_never_severe,stdev_value_never_severe,mean_log_value_never_severe,stdev_log_value_never_severe' s from dual union all select row_number() over (order by cohort,loinc,days_since_admission) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(loinc as varchar2(2000)) || ',' || cast(days_since_admission as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(mean_value_all as varchar2(2000)) || ',' || cast(stdev_value_all as varchar2(2000)) || ',' || cast(mean_log_value_all as varchar2(2000)) || ',' || cast(stdev_log_value_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) || ',' || cast(mean_value_ever_severe as varchar2(2000)) || ',' || cast(stdev_value_ever_severe as varchar2(2000)) || ',' || cast(mean_log_value_ever_severe as varchar2(2000)) || ',' || cast(stdev_log_value_ever_severe as varchar2(2000)) || ',' || cast(pts_never_severe as varchar2(2000)) || ',' || cast(mean_value_never_severe as varchar2(2000)) || ',' || cast(stdev_value_never_severe as varchar2(2000)) || ',' || cast(mean_log_value_never_severe as varchar2(2000)) || ',' || cast(stdev_log_value_never_severe as varchar2(2000)) from jaspreetk.fource_Labs
--union all select 9999999 z, '' from dual
) t order by z;
spool off


spool DiagProcMed-BCH.csv
select s DiagProcMedCSV from ( select 0 z, 'siteid,cohort,concept_type,concept_code,pts_all_before_adm,pts_all_since_adm,pts_all_dayN14toN1,pts_all_day0to29,pts_all_day30to89,pts_all_day30plus,pts_all_day90plus,pts_all_1st_day0to29,pts_all_1st_day30plus,pts_all_1st_day90plus,pts_ever_severe_before_adm,pts_ever_severe_since_adm,pts_ever_severe_dayN14toN1,pts_ever_severe_day0to29,pts_ever_severe_day30to89,pts_ever_severe_day30plus,pts_ever_severe_day90plus,pts_ever_severe_1st_day0to29,pts_ever_severe_1st_day30plus,pts_ever_severe_1st_day90plus' s from dual union all select row_number() over (order by cohort,concept_type,concept_code) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(concept_type as varchar2(2000)) || ',' || cast(concept_code as varchar2(2000)) || ',' || cast(pts_all_before_adm as varchar2(2000)) || ',' || cast(pts_all_since_adm as varchar2(2000)) || ',' || cast(pts_all_dayN14toN1 as varchar2(2000)) || ',' || cast(pts_all_day0to29 as varchar2(2000)) || ',' || cast(pts_all_day30to89 as varchar2(2000)) || ',' || cast(pts_all_day30plus as varchar2(2000)) || ',' || cast(pts_all_day90plus as varchar2(2000)) || ',' || cast(pts_all_1st_day0to29 as varchar2(2000)) || ',' || cast(pts_all_1st_day30plus as varchar2(2000)) || ',' || cast(pts_all_1st_day90plus as varchar2(2000)) || ',' || cast(pts_ever_severe_before_adm as varchar2(2000)) || ',' || cast(pts_ever_severe_since_adm as varchar2(2000)) || ',' || cast(pts_ever_severe_dayN14toN1 as varchar2(2000)) || ',' || cast(pts_ever_severe_day0to29 as varchar2(2000)) || ',' || cast(pts_ever_severe_day30to89 as varchar2(2000)) || ',' || cast(pts_ever_severe_day30plus as varchar2(2000)) || ',' || cast(pts_ever_severe_day90plus as varchar2(2000)) || ',' || cast(pts_ever_severe_1st_day0to29 as varchar2(2000)) || ',' || cast(pts_ever_severe_1st_day30plus as varchar2(2000)) || ',' || cast(pts_ever_severe_1st_day90plus as varchar2(2000)) from jaspreetk.fource_DiagProcMed
--union all select 9999999 z, '' from dual
) t order by z;
spool off


spool RaceByLocalCode-BCH.csv
select s RaceByLocalCodeCSV from ( select 0 z, 'siteid,cohort,race_local_code,race_4ce,pts_all,pts_ever_severe' s from dual union all select row_number() over (order by cohort,race_local_code) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(race_local_code as varchar2(2000)) || ',' || cast(race_4ce as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) from jaspreetk.fource_RaceByLocalCode
--union all select 9999999 z, '' from dual
) t order by z;
spool off


spool RaceBy4CECode-BCH.csv
select s RaceBy4CECodeCSV from ( select 0 z, 'siteid,cohort,race_4ce,pts_all,pts_ever_severe' s from dual union all select row_number() over (order by cohort,race_4ce) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(race_4ce as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) from jaspreetk.fource_RaceBy4CECode
--union all select 9999999 z, '' from dual
) t order by z;
spool off


spool LabCodes-BCH.csv

select s LabCodesCSV from ( select 0 z, 'siteid,fource_loinc,fource_lab_units,fource_lab_name,scale_factor,local_lab_code,local_lab_units,local_lab_name,notes' s from dual union all select row_number() over (order by fource_loinc,local_lab_code,local_lab_units) z, cast(siteid as varchar2(2000)) || ',' || cast(fource_loinc as varchar2(2000)) || ',' || cast(fource_lab_units as varchar2(2000)) || ',' || cast(fource_lab_name as varchar2(2000)) || ',' || cast(scale_factor as varchar2(2000)) || ',' || cast(local_lab_code as varchar2(2000)) || ',' || cast(local_lab_units as varchar2(2000)) || ',' || cast(local_lab_name as varchar2(2000)) || ',' || cast(notes as varchar2(2000)) from jaspreetk.fource_LabCodes where scale_factor <> 0 -- union all select 9999999 z, '' from dual
) t order by z;

spool off

spool LocalDailyCounts.csv
select s LocalDailyCountsCSV from ( select 0 z, 'siteid,cohort,calendar_date,cumulative_pts_all,cumulative_pts_icu,cumulative_pts_dead,cumulative_pts_severe,cumulative_pts_severe_icu,cumulative_pts_severe_dead,pts_in_hosp_on_this_date,pts_in_icu_on_this_date,pts_severe_in_hosp_on_date,pts_severe_in_icu_on_date' s from dual union all select row_number() over (order by cohort,calendar_date) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || to_char(calendar_date, 'YYYY-MM-DD') || ',' || cast(cumulative_pts_all as varchar2(2000)) || ',' || cast(cumulative_pts_icu as varchar2(2000)) || ',' || cast(cumulative_pts_dead as varchar2(2000)) || ',' || cast(cumulative_pts_severe as varchar2(2000)) || ',' || cast(cumulative_pts_severe_icu as varchar2(2000)) || ',' || cast(cumulative_pts_severe_dead as varchar2(2000)) || ',' || cast(pts_in_hosp_on_this_date as varchar2(2000)) || ',' || cast(pts_in_icu_on_this_date as varchar2(2000)) || ',' || cast(pts_severe_in_hosp_on_date as varchar2(2000)) || ',' || cast(pts_severe_in_icu_on_date as varchar2(2000)) from jaspreetk.fource_LocalDailyCounts -- union all select 9999999 z, '' from dual
) t order by z;
spool off


spool LocalClinicalCourse.csv
select s LocalClinicalCourseCSV from ( select 0 z, 'siteid,cohort,days_since_admission,pts_all_in_hosp,pts_all_in_icu,pts_all_dead,pts_severe_by_this_day,pts_ever_severe_in_hosp,pts_ever_severe_in_icu,pts_ever_severe_dead' s from dual union all select row_number() over (order by cohort,days_since_admission) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(days_since_admission as varchar2(2000)) || ',' || cast(pts_all_in_hosp as varchar2(2000)) || ',' || cast(pts_all_in_icu as varchar2(2000)) || ',' || cast(pts_all_dead as varchar2(2000)) || ',' || cast(pts_severe_by_this_day as varchar2(2000)) || ',' || cast(pts_ever_severe_in_hosp as varchar2(2000)) || ',' || cast(pts_ever_severe_in_icu as varchar2(2000)) || ',' || cast(pts_ever_severe_dead as varchar2(2000)) from jaspreetk.fource_LocalClinicalCourse --union all select 9999999 z, '' from dual
) t order by z;
spool off


spool LocalAgeSex.csv
select s LocalAgeSexCSV from ( select 0 z, 'siteid,cohort,age_group,mean_age,sex,pts_all,pts_ever_severe' s from dual union all select row_number() over (order by cohort,age_group,sex) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(age_group as varchar2(2000)) || ',' || cast(mean_age as varchar2(2000)) || ',' || cast(sex as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) from jaspreetk.fource_LocalAgeSex --union all select 9999999 z, '' from dual
) t order by z;
spool off


spool LocalLabs.csv
select s LocalLabsCSV from ( select 0 z, 'siteid,cohort,loinc,days_since_admission,pts_all,mean_value_all,stdev_value_all,mean_log_value_all,stdev_log_value_all,pts_ever_severe,mean_value_ever_severe,stdev_value_ever_severe,mean_log_value_ever_severe,stdev_log_value_ever_severe,pts_never_severe,mean_value_never_severe,stdev_value_never_severe,mean_log_value_never_severe,stdev_log_value_never_severe' s from dual
union all select row_number() over (order by cohort,loinc,days_since_admission) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(loinc as varchar2(2000)) || ',' || cast(days_since_admission as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(mean_value_all as varchar2(2000)) || ',' || cast(stdev_value_all as varchar2(2000)) || ',' || cast(mean_log_value_all as varchar2(2000)) || ',' || cast(stdev_log_value_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) || ',' || cast(mean_value_ever_severe as varchar2(2000)) || ',' || cast(stdev_value_ever_severe as varchar2(2000)) || ',' || cast(mean_log_value_ever_severe as varchar2(2000)) || ',' || cast(stdev_log_value_ever_severe as varchar2(2000)) || ',' || cast(pts_never_severe as varchar2(2000)) || ',' || cast(mean_value_never_severe as varchar2(2000)) || ',' || cast(stdev_value_never_severe as varchar2(2000)) || ',' || cast(mean_log_value_never_severe as varchar2(2000)) || ',' || cast(stdev_log_value_never_severe as varchar2(2000)) from jaspreetk.fource_LocalLabs --union all select 9999999 z, '' from dual
) t order by z;

spool off


spool LocalDiagProcMed.csv
select s LocalDiagProcMedCSV from ( select 0 z, 'siteid,cohort,concept_type,concept_code,pts_all_before_adm,pts_all_since_adm,pts_all_dayN14toN1,pts_all_day0to29,pts_all_day30to89,pts_all_day30plus,pts_all_day90plus,pts_all_1st_day0to29,pts_all_1st_day30plus,pts_all_1st_day90plus,pts_ever_severe_before_adm,pts_ever_severe_since_adm,pts_ever_severe_dayN14toN1,pts_ever_severe_day0to29,pts_ever_severe_day30to89,pts_ever_severe_day30plus,pts_ever_severe_day90plus,pts_ever_severe_1st_day0to29,pts_ever_severe_1st_day30plus,pts_ever_severe_1st_day90plus' s from dual union all select row_number() over (order by cohort,concept_type,concept_code) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(concept_type as varchar2(2000)) || ',' || cast(concept_code as varchar2(2000)) || ',' || cast(pts_all_before_adm as varchar2(2000)) || ',' || cast(pts_all_since_adm as varchar2(2000)) || ',' || cast(pts_all_dayN14toN1 as varchar2(2000)) || ',' || cast(pts_all_day0to29 as varchar2(2000)) || ',' || cast(pts_all_day30to89 as varchar2(2000)) || ',' || cast(pts_all_day30plus as varchar2(2000)) || ',' || cast(pts_all_day90plus as varchar2(2000)) || ',' || cast(pts_all_1st_day0to29 as varchar2(2000)) || ',' || cast(pts_all_1st_day30plus as varchar2(2000)) || ',' || cast(pts_all_1st_day90plus as varchar2(2000)) || ',' || cast(pts_ever_severe_before_adm as varchar2(2000)) || ',' || cast(pts_ever_severe_since_adm as varchar2(2000)) || ',' || cast(pts_ever_severe_dayN14toN1 as varchar2(2000)) || ',' || cast(pts_ever_severe_day0to29 as varchar2(2000)) || ',' || cast(pts_ever_severe_day30to89 as varchar2(2000)) || ',' || cast(pts_ever_severe_day30plus as varchar2(2000)) || ',' || cast(pts_ever_severe_day90plus as varchar2(2000)) || ',' || cast(pts_ever_severe_1st_day0to29 as varchar2(2000)) || ',' || cast(pts_ever_severe_1st_day30plus as varchar2(2000)) || ',' || cast(pts_ever_severe_1st_day90plus as varchar2(2000)) from jaspreetk.fource_LocalDiagProcMed --union all select 9999999 z, '' from dual
) t order by z;
spool off


spool LocalRaceByLocalCode.csv
select s LocalRaceByLocalCodeCSV from ( select 0 z, 'siteid,cohort,race_local_code,race_4ce,pts_all,pts_ever_severe' s from dual union all select row_number() over (order by cohort,race_local_code) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(race_local_code as varchar2(2000)) || ',' || cast(race_4ce as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) from jaspreetk.fource_LocalRaceByLocalCode --union all select 9999999 z, '' from dual
) t order by z;
spool off


spool LocalRaceBy4CECode.csv
select s LocalRaceBy4CECodeCSV from ( select 0 z, 'siteid,cohort,race_4ce,pts_all,pts_ever_severe' s from dual union all select row_number() over (order by cohort,race_4ce) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(race_4ce as varchar2(2000)) || ',' || cast(pts_all as varchar2(2000)) || ',' || cast(pts_ever_severe as varchar2(2000)) from jaspreetk.fource_LocalRaceBy4CECode --union all select 9999999 z, '' from dual
) t order by z;
spool off


spool LocalPatientClinicalCourse.csv
select s LocalPatientClinicalCourseCSV from ( select 0 z, 'siteid,cohort,patient_num,days_since_admission,calendar_date,in_hospital,severe,in_icu,dead' s from dual union all select row_number() over (order by cohort,patient_num,days_since_admission) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(patient_num as varchar2(2000)) || ',' || cast(days_since_admission as varchar2(2000)) || ',' || cast(calendar_date as varchar2(2000)) || ',' || cast(in_hospital as varchar2(2000)) || ',' || cast(severe as varchar2(2000)) || ',' || cast(in_icu as varchar2(2000)) || ',' || cast(dead as varchar2(2000)) from jaspreetk.fource_LocalPatClinicalCourse --union all select 9999999 z, '' from dual
) t order by z;
spool off


spool LocalPatientSummary.csv
select s LocalPatientSummaryCSV from ( select 0 z, 'siteid,cohort,patient_num,admission_date,source_data_updated_date,days_since_admission,last_discharge_date,still_in_hospital,severe_date,severe,icu_date,icu,death_date,dead,age_group,age,sex' s from dual union all select row_number() over (order by cohort,patient_num) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(patient_num as varchar2(2000)) || ',' || cast(admission_date as varchar2(2000)) || ',' || to_char(source_data_updated_date, 'YYYY-MM-DD') || ',' || cast(days_since_admission as varchar2(2000)) || ',' || to_char(last_discharge_date, 'YYYY-MM-DD') || ',' || cast(still_in_hospital as varchar2(2000)) || ',' || to_char(severe_date, 'YYYY-MM-DD') || ',' || cast(severe as varchar2(2000)) || ',' || to_char(icu_date, 'YYYY-MM-DD') || ',' || cast(icu as varchar2(2000)) || ',' || to_char(death_date, 'YYYY-MM-DD') || ',' || cast(dead as varchar2(2000)) || ',' || cast(age_group as varchar2(2000)) || ',' || cast(age as varchar2(2000)) || ',' || cast(sex as varchar2(2000)) from jaspreetk.fource_LocalPatientSummary --union all select 9999999 z, '' from dual
) t order by z;
spool off


spool LocalPatientObservations.csv
select s LocalPatientObservationsCSV from ( select 0 z, 'siteid,cohort,patient_num,days_since_admission,concept_type,concept_code,value' s from dual union all select row_number() over (order by cohort,patient_num,days_since_admission,concept_type,concept_code) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(patient_num as varchar2(2000)) || ',' || cast(days_since_admission as varchar2(2000)) || ',' || cast(concept_type as varchar2(2000)) || ',' || cast(concept_code as varchar2(2000)) || ',' || cast(value as varchar2(2000)) from jaspreetk.fource_LocalPatObservations --union all select 9999999 z, '' from dual
) t order by z;
spool off


spool LocalPatientRace.csv
select s LocalPatientRaceCSV from ( select 0 z, 'siteid,cohort,patient_num,race_local_code,race_4ce' s from dual union all select row_number() over (order by cohort,patient_num,race_local_code) z, cast(siteid as varchar2(2000)) || ',' || cast(cohort as varchar2(2000)) || ',' || cast(patient_num as varchar2(2000)) || ',' || cast(race_local_code as varchar2(2000)) || ',' || cast(race_4ce as varchar2(2000)) from jaspreetk.fource_LocalPatientRace --union all select 9999999 z, '' from dual
) t order by z;
spool off


spool LocalPatientMapping.csv
select s LocalPatientMappingCSV from ( select 0 z, 'siteid,patient_num,study_num' s from dual union all select row_number() over (order by patient_num) z, cast(siteid as varchar2(2000)) || ',' || cast(patient_num as varchar2(2000)) || ',' || cast(study_num as varchar2(2000)) from jaspreetk.fource_LocalPatientMapping --union all select 9999999 z, '' from dual
) t order by z;
spool off

