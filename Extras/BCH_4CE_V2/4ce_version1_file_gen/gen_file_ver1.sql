set pagesize 0
set echo off
set feedback off
set term off
set linesize 4000
set verify off
set trimspool on

spool DailyCounts-BCH.csv.1
        select s DailyCountsCSV
            from (
                select 0 i, 'siteid,calendar_date,cumulative_patients_all,cumulative_patients_severe,cumulative_patients_dead,'
                    ||'num_patients_in_hospital_on_this_date,num_patients_in_hospital_and_severe_on_this_date' s from dual
                union all 
                select row_number() over (order by calendar_date) i,
                    siteid
                    ||','||cast(to_char(calendar_date,'YYYY-MM-DD') as varchar(50)) --YYYY-MM-DD
                    ||','||cast(cumulative_patients_all as varchar(50))
                    ||','||cast(cumulative_patients_severe as varchar(50))
                    ||','||cast(cumulative_patients_dead as varchar(50))
                    ||','||cast(num_pat_in_hosp_on_date as varchar(50))
                    ||','||cast(num_pat_in_hospsevere_on_date as varchar(50))
                from covid_daily_counts
                union all 
                select 9999999, '' from dual--Add a blank row to make sure the last line in the file with data ends with a line feed.
            ) t
            order by i;
spool off;


spool ClinicalCourse-BCH.csv.1 ;   
        select s ClinicalCourseCSV
            from (
                select 0 i, 'siteid,days_since_admission,num_patients_all_still_in_hospital,num_patients_ever_severe_still_in_hospital' s from dual
                union all 
                select row_number() over (order by days_since_admission) i,
                    siteid
                    ||','||cast(days_since_admission as varchar(50))
                    ||','||cast(num_pat_all_cur_in_hosp as varchar(50))
                    ||','||cast(num_pat_ever_severe_cur_hosp as varchar(50))
                from covid_clinical_course
                union all 
                select 9999999, '' from dual  --Add a blank row to make sure the last line in the file with data ends with a line feed.
            ) t
            order by i;
spool off;

spool Demographics-BCH.csv.1;   
        select s DemographicsCSV
            from (
                select 0 i, 'siteid,sex,age_group,race,num_patients_all,num_patients_ever_severe' s from dual
                union all 
                select row_number() over (order by sex, age_group, race) i,
                    siteid
                    ||','||cast(sex as varchar(50))
                    ||','||cast(age_group as varchar(50))
                    ||','||cast(race as varchar(50))
                    ||','||cast(num_patients_all as varchar(50))
                    ||','||cast(num_patients_ever_severe as varchar(50))
                from covid_demographics
                union all select 9999999, '' from dual--Add a blank row to make sure the last line in the file with data ends with a line feed.
            ) t
            order by i;  
spool off;

spool Labs-BCH.csv.1;  
        select s LabsCSV
            from (
                select 0 i, 'siteid,loinc,days_since_admission,units,'
                    ||'num_patients_all,mean_value_all,stdev_value_all,mean_log_value_all,stdev_log_value_all,'
                    ||'num_patients_ever_severe,mean_value_ever_severe,stdev_value_ever_severe,mean_log_value_ever_severe,stdev_log_value_ever_severe' s
                from dual    
                union all 
                select row_number() over (order by loinc, days_since_admission) i,
                    siteid
                    ||','||cast(loinc as varchar(50))
                    ||','||cast(days_since_admission as varchar(50))
                    ||','||cast(units as varchar(50))
                    ||','||cast(num_patients_all as varchar(50))
                    ||','||cast(mean_value_all as varchar(50))
                    ||','||cast(stdev_value_all as varchar(50))
                    ||','||cast(mean_log_value_all as varchar(50))
                    ||','||cast(stdev_log_value_all as varchar(50))
                    ||','||cast(num_patients_ever_severe as varchar(50))
                    ||','||cast(mean_value_ever_severe as varchar(50))
                    ||','||cast(STDEV_VALUE_EVER_SEVERE as varchar(50))
                    ||','||cast(mean_log_value_ever_severe as varchar(50))
                    ||','||cast(stdev_log_value_ever_severe as varchar(50))
                from covid_labs
                union all select 9999999, '' from dual--Add a blank row to make sure the last line in the file with data ends with a line feed.
            ) t
            order by i;
spool off;


spool Diagnoses-BCH.csv.1 ; 
        select s DiagnosesCSV
            from (
                select 0 i, 'siteid,icd_code_3chars,icd_version,'
                    ||'num_patients_all_before_admission,num_patients_all_since_admission,'
                    ||'num_patients_ever_severe_before_admission,num_patients_ever_severe_since_admission' s
                from dual    
                union all 
                select row_number() over (order by num_pat_all_since_admission desc, num_pat_all_before_admission desc) i,
                    siteid
                    ||','||cast(icd_code_3chars as varchar(50))
                    ||','||cast(icd_version as varchar(50))
                    ||','||cast(num_pat_all_before_admission as varchar(50))
                    ||','||cast(num_pat_all_since_admission as varchar(50))
                    ||','||cast(num_pat_ever_severe_before_adm as varchar(50))
                    ||','||cast(num_pat_ever_severe_since_adm as varchar(50))
                from covid_diagnoses
                union all select 9999999, '' from dual--Add a blank row to make sure the last line in the file with data ends with a line feed.
            ) t
            order by i;
spool off;

spool Medications-BCH.csv.1 ; 
        select s MedicationsCSV
            from (
                select 0 i, 'siteid,med_class,'
                    ||'num_patients_all_before_admission,num_patients_all_since_admission,'
                    ||'num_patients_ever_severe_before_admission,num_patients_ever_severe_since_admission' s
                from dual    
                union all 
                select row_number() over (order by num_pat_all_since_admission desc, num_pat_all_before_admission desc) i,
                    siteid
                    ||','||cast(med_class as varchar(50))
                    ||','||cast(num_pat_all_before_admission as varchar(50))
                    ||','||cast(num_pat_all_since_admission as varchar(50))
                    ||','||cast(num_pat_ever_severe_before_adm as varchar(50))
                    ||','||cast(num_pat_ever_severe_since_adm as varchar(50))
                from covid_medications
                union all select 9999999, '' from dual    ) t
            order by i;
spool off;



spool LocalPatientClinicalCourse.csv.1
select s PatientClinicalCourseCSV
		from (
			select 0 i, 'siteid,patient_num,days_since_admission,calendar_date,in_hospital,severe,deceased' s FROM DUAL
			union all 
			select row_number() over (order by patient_num, days_since_admission) i,
				siteid
                ||','||cast(patient_num as varchar2(50))
                ||','||to_char(days_since_admission) 
                ||','||to_char(calendar_date,'YYYY-MM-DD')  --YYYY-MM-DD
                ||','||to_char(in_hospital)
                ||','||to_char(severe)
                ||','||to_char(deceased)
			from PatientClinicalCourse
			union all select 9999999, '' FROM DUAL --Add a blank row to make sure the last line in the file with data ends with a line feed.
		) t
		order by i ;
spool off


spool LocalPatientSummary.csv.1
	select s PatientSummaryCSV
		from (
			select 0 i, 'siteid,patient_num,admission_date,days_since_admission,last_discharge_date,still_in_hospital,'
				||'severe_date,severe,death_date,deceased,sex,age_group,race,race_collected' S FROM DUAL
			union all 	
            select row_number() over (order by admission_date, patient_num) i,
				siteid
                ||','||cast(patient_num as varchar2(50))
                ||','||to_char(admission_date,'YYYY-MM-DD')  --YYYY-MM-DD
                ||','||to_char(days_since_admission)              
                ||','||to_char(last_discharge_date,'YYYY-MM-DD')  --YYYY-MM-DD
                ||','||to_char(still_in_hospital)    
                ||','||to_char(severe_date,'YYYY-MM-DD')  --YYYY-MM-DD
                ||','||to_char(severe)  
                ||','||to_char(death_date,'YYYY-MM-DD')  --YYYY-MM-DD
                ||','||to_char(deceased) 
                ||','||to_char(sex) 
                ||','||to_char(age_group) 
                ||','||to_char(race) 
                ||','||to_char(race_collected) 
			from PatientSummary
			union all select 9999999, '' FROM DUAL
		) t
		order by i;
spool off


spool LocalPatientObservations.csv.1
	select s PatientObservationsCSV
		from (
			select 0 i, 'siteid,patient_num,days_since_admission,concept_type,concept_code,value' s FROM DUAL
			union all 
			select row_number() over (order by patient_num, concept_type, concept_code, days_since_admission) i,
            siteid
                ||','||cast(patient_num as varchar2(50))
                ||','||to_char(days_since_admission) 
                ||','||to_char(concept_type)
                ||','||to_char(concept_code)
                ||','||to_char(value)
			from PatientObservations
			union all select 9999999, '' FROM DUAL --Add a blank row to make sure the last line in the file with data ends with a line feed.
		) t
		order by i;
spool off


spool LocalPatientMapping.csv.1
	select s PatientMappingCSV
		from (
			select 0 i, 'siteid,patient_num,study_num' s FROM DUAL
			union all 
			select row_number() over (order by patient_num) i,
             siteid
                ||','||to_char(patient_num)
                ||','||to_char(study_num)
			from PatientMapping
			union all select 9999999, '' FROM DUAL --Add a blank row to make sure the last line in the file with data ends with a line feed.
		) t
		order by i;
spool off


