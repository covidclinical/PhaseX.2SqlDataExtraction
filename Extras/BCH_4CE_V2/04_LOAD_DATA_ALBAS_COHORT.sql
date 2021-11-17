
--Extracts data for Albas cohort --'AllAdm'
-- start date 01/01/2019 for cohort
truncate table fource_config;

begin
TM_LOG_PKG.log_msg( -222,'Step1 Load fource_config Start ', 'X'); 
insert into fource_config
	select 'BCH', -- siteid
		1, -- race_data_available
		1, -- icu_data_available
		1, -- death_data_available
		'ICD9:', -- code_prefix_icd9cm
		'ICD10:', -- code_prefix_icd10cm
		to_date('06-24-2021','mm-dd-yyyy'), -- source_data_updated_date
		-- Phase 1
		1, -- include_extra_cohorts_phase1 (please set to 1 if allowed by your IRB and institution)
		0, -- obfuscation_blur
		0,--10, -- obfuscation_small_count_mask
		0,--1, -- obfuscation_small_count_delete
		0, -- obfuscation_agesex
		0, -- output_phase1_as_columns
		1, -- output_phase1_as_csv
		0, -- save_phase1_as_columns
		'dbo_FourCE_', -- save_phase1_as_prefix (don't use "4CE" since it starts with a number)
		-- Phase 2
		1, -- include_extra_cohorts_phase2 (please set to 1 if allowed by your IRB and institution) 
		1, -- replace_patient_num 
		0, -- output_phase2_as_columns
		1, -- output_phase2_as_csv
		0, -- save_phase2_as_columns
		'dbo_FourCE_', -- save_phase2_as_prefix (don't use "4CE" since it starts with a number
        to_date('01-JAN-2015')
    from dual;
    TM_LOG_PKG.log_msg( -222,'Step1 Load fource_config Rows '||sql%rowcount||' End ', 'X');  
commit;
end;
/

--------------------------------------------------------------------------------
-- Lab mappings report (for debugging lab mappings)
--------------------------------------------------------------------------------
-- Get a list of all the codes and units in the data for 4CE labs since 1/1/2019
--Lab map table loaded before - separately .
truncate table fource_lab_map_report ;


begin
TM_LOG_PKG.log_msg( -222,'Step2 Load fource_lab_map_report Start ', 'X');  

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
    TM_LOG_PKG.log_msg( -222,'Step2 Load fource_lab_map_report Rows '||sql%rowcount||' End ', 'X');          
commit;
end;
/



---------------------------------------------------------------------------------
-- Procedure mappings
-- Loading fource_cohort_config
--------------------------------------------------------------------------------


truncate table fource_cohort_config ;
truncate table fource_covid_tests ;
--step 5
begin
TM_LOG_PKG.log_msg( -222,'Step3 Load fource_covid_tests Start ', 'X');  


insert into fource_covid_tests
	select distinct f.patient_num, m.code, trunc(start_date)
		from i2b2_user.observation_fact f --with (nolock)
			inner join fource_code_map m
             on   f.CONCEPT_CD||lower(f.TVAL_CHAR ) = m.local_code and m.code in ('covidpos','covidneg')
            union all
            	select distinct f.patient_num, m.code, trunc(start_date)
		from i2b2_user.observation_fact f --with (nolock)
			inner join fource_code_map m
             on   f.CONCEPT_CD = m.local_code and m.code in ('covidU071');
           TM_LOG_PKG.log_msg( -222,'Step3 Load fource_covid_tests Rows '||sql%rowcount||' End ', 'X');         
commit;
end;
/

--select * from fource_covid_tests;
--------------------------------------------------------------------------------
-- Create a list of patient admission dates.
--------------------------------------------------------------------------------
truncate table fource_admissions ;
begin
TM_LOG_PKG.log_msg( -222,'Step4 Load fource_admissions Start ', 'X');  
insert into fource_admissions
    select *
        from (
            select distinct patient_num, start_date admission_date, nvl(end_date,to_date('01/01/2199','mm/dd/rrrr')) discharge_date
            from (
                select to_number(patient_num) patient_num, start_date, end_date
                    from i2b2_user.visit_dimension
                    where inout_cd in (select local_code from fource_code_map where code = 'inpatient_inout_cd')
                union all
                select to_number(patient_num) patient_num, start_date, end_date
                    from i2b2_user.visit_dimension v
                    where location_cd in (select local_code from fource_code_map where code = 'inpatient_location_cd')
                union all
                select f.patient_num, f.start_date, nvl(f.end_date,v.end_date)
                    from i2b2_user.observation_fact f
                        inner join i2b2_user.visit_dimension v
                            on v.encounter_num=f.encounter_num and v.patient_num=f.patient_num
                    where f.concept_cd in (select local_code from fource_code_map where code = 'inpatient_concept_cd')
            ) t
        ) t
        where (admission_date >= to_date('01/01/2019','mm/dd/yyyy'  ) ) and (discharge_date >= admission_date);


         TM_LOG_PKG.log_msg( -222,'Step4 Load fource_admissions Rows  '||sql%rowcount||' End ', 'X'); 
         commit;
end;
 /    
--------------------------------------------------------------------------------
-- Create a list of dates where patients were in the ICU.
--------------------------------------------------------------------------------
truncate table fource_icu ;
--step7
begin
TM_LOG_PKG.log_msg( -222,'Step5 Load fource_icu Start ', 'X');   

insert into fource_icu
	select *
	from (
		select distinct patient_num,  start_date, nvl(end_date,to_date('1/1/2199','mm/dd/rrrr')) end_date
		from (
			select  to_number(patient_num) patient_num, start_date, end_date
				from i2b2_user.visit_dimension
				where inout_cd in (select local_code from fource_code_map where code = 'icu_inout_cd')
			union all
			select  to_number(patient_num) patient_num, start_date, end_date
				from i2b2_user.visit_dimension v
				where location_cd in (select local_code from fource_code_map where code = 'icu_location_cd')
			union all
			select f.patient_num, f.start_date, nvl(f.end_date,v.end_date)
				from i2b2_user.observation_fact f
					inner join i2b2_user.visit_dimension v
						on v.encounter_num=f.encounter_num and v.patient_num=f.patient_num
				where f.concept_cd in (select local_code from fource_code_map where code = 'icu_concept_cd')
		) t
	) t
	where (start_date >= to_date('01/01/2019','mm/dd/yyyy') ) and (end_date >= start_date) ;
TM_LOG_PKG.log_msg( -222,'Step5 Load fource_icu Rows '||sql%rowcount||' End ', 'X'); 
   
    commit;
end;    
 /   
--------------------------------------------------------------------------------
-- Create a list of dates when patients died.
--------------------------------------------------------------------------------
truncate table fource_death ;
--step8
begin
TM_LOG_PKG.log_msg( -222,'Step6 Load fource_death Start ', 'X');  
insert into fource_death
	select patient_num, nvl(death_date,to_date('01/01/1900','mm/dd/rrrr')) 
	from i2b2_user.patient_dimension
	where (death_date is not null or vital_status_cd in ('Y'))
--		and patient_num not in (select patient_num from fource_covid_tests)
		and death_date >= to_date('01/01/2019','mm/dd/rrrr');
        
         TM_LOG_PKG.log_msg( -222,'Step6 Load fource_death Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;
 /       

begin
    TM_LOG_PKG.log_msg( -222,'Step7 Load fource_cohort_config Rows Start', 'X'); 
insert into fource_cohort_config
with t as (
	select to_date('01/01/2019','mm/dd/rrrr') start_date, nvl(source_data_updated_date,sysdate) end_date
	from fource_config
    )
	select 'AllAdm', 1, 1, end_date, start_date, end_date from t ;
	--union all select 'AllNotAdm', 1, 1, end_date, start_date, end_date from t;
         TM_LOG_PKG.log_msg( -222,'Step7 Load fource_cohort_config Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;
/
truncate table fource_first_covid_tests ;

begin
 TM_LOG_PKG.log_msg( -222,'Step8 Load fource_first_covid_tests Rows Start ', 'X'); 
insert into fource_first_covid_tests
	select patient_num,
			min(case when test_result='covidpos' then test_date else null end),
			min(case when test_result='covidneg' then test_date else null end),
			min(case when test_result='covidU071' then test_date else null end)
		from fource_covid_tests
		group by patient_num;
        TM_LOG_PKG.log_msg( -222,'Step8 Load fource_first_covid_tests Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;
/

--------------------------------------------------------------------------------
-- Get the list of patients who will be in the cohorts.
-- By default, these will be patients who had an admission between 7 days before
--   and 14 days after their first covid positive test date.
--------------------------------------------------------------------------------


truncate table fource_cohort_patients ;

begin
        TM_LOG_PKG.log_msg( -222,'Step9 Load fource_cohort_patients Rows Start ', 'X'); 
insert into fource_cohort_patients
	select c.cohort, a.patient_num, min(a.admission_date), c.source_data_updated_date, 0, null, null
	from fource_admissions a
		inner join fource_cohort_config c
			on a.admission_date >= c.earliest_adm_date and a.admission_date <= c.latest_adm_date
	where c.cohort='AllAdm'
--		and a.patient_num not in (select patient_num from fource_cohort_patients)
	group by c.cohort, a.patient_num, c.source_data_updated_date;
        TM_LOG_PKG.log_msg( -222,'Step9 Load fource_cohort_patients Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;
 /   
    
-- Get all patients who have an encounter

begin
TM_LOG_PKG.log_msg( -222,'Step10 Load fource_cohort_patients Rows Start', 'X'); 
insert into fource_cohort_patients
	select c.cohort, v.patient_num, min(v.start_date), c.source_data_updated_date, 0, null, null
	from i2b2_user.visit_dimension v
		inner join fource_cohort_config c
			on v.start_date >= c.earliest_adm_date and v.start_date <= c.latest_adm_date
	where c.cohort='AllNotAdm'
--		and v.patient_num not in (select patient_num from fource_cohort_patients)
	group by c.cohort, v.patient_num, c.source_data_updated_date;
TM_LOG_PKG.log_msg( -222,'Step10 Load fource_cohort_patients Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;    
  /  
--------------------------------------------------------------------------------
-- Add optional cohorts that contain all patients tested for COVID-19
--------------------------------------------------------------------------------


-- Create cohorts for patients who were admitted
begin
TM_LOG_PKG.log_msg( -222,'Step11 Load fource_cohort_config Rows Start', 'X'); 
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
			where c.cohort like 'PosAdm%'  )
        where (select include_extra_cohorts_phase1 from fource_config where rownum = 1) = 1 
        or (select include_extra_cohorts_phase2 from fource_config where rownum = 1) = 1;
        
TM_LOG_PKG.log_msg( -222,'Step11 Load fource_cohort_config Rows '||sql%rowcount||' End ', 'X'); 
commit;
end; 
/
-- Add the patients for those cohorts
begin
TM_LOG_PKG.log_msg( -222,'Step12 Load fource_cohort_patients Rows Start', 'X'); 
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
TM_LOG_PKG.log_msg( -222,'Step12 Load fource_cohort_patients Rows '||sql%rowcount||' End ', 'X'); 
commit;
end; 
/

-- Create cohorts for patients who were not admitted
begin
TM_LOG_PKG.log_msg( -222,'Step13 Load fource_cohort_config Rows Start ', 'X'); 
insert into fource_cohort_config
		select replace(c.cohort,'Adm','NotAdm'), 
				g.include_extra_cohorts_phase1, g.include_extra_cohorts_phase2,
				c.source_data_updated_date, c.earliest_adm_date, c.latest_adm_date
			from fource_cohort_config c cross apply fource_config g
			where c.cohort like 'PosAdm%' or c.cohort like 'NegAdm%' or c.cohort like 'U071Adm%';
TM_LOG_PKG.log_msg( -222,'Step13 Load fource_cohort_config Rows '||sql%rowcount||' End ', 'X'); 
commit;
end; 
/

-- Add the patients for those cohorts using the test or diagnosis date as the "admission" (index) date
begin
TM_LOG_PKG.log_msg( -222,'Step14 Load fource_cohort_config Rows Start ', 'X'); 
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

TM_LOG_PKG.log_msg( -222,'Step14 Load fource_cohort_config Rows '||sql%rowcount||' End ', 'X'); 
commit;
end; 
/
--------------------------------------------------------------------------------
-- Add additional custom cohorts here
--------------------------------------------------------------------------------


-- Get a distinct list of patients
truncate table fource_patients ;
begin
TM_LOG_PKG.log_msg( -222,'Step15 Load fource_patients Rows Start ', 'X'); 
insert into fource_patients
	select patient_num, min(admission_date)
		from fource_cohort_patients
		group by patient_num;
TM_LOG_PKG.log_msg( -222,'Step15 Load fource_patients Rows '||sql%rowcount||' End ', 'X'); 
commit;
end; 
/
-- Create the table to store the observations
truncate table fource_observations ;
--------------------------------------------------------------------------------
-- Add covid tests
--------------------------------------------------------------------------------

begin
TM_LOG_PKG.log_msg( -222,'Step16 Load fource_observations Rows Start ', 'X'); 
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
TM_LOG_PKG.log_msg( -222,'Step16 Load fource_observations Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;
/
--------------------------------------------------------------------------------
-- Add children who develop MIS-C
--------------------------------------------------------------------------------
begin
TM_LOG_PKG.log_msg( -222,'Step17 Load fource_observations Rows Start ', 'X'); 
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
            
TM_LOG_PKG.log_msg( -222,'Step17 Load fource_observations Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;
 /           
--create index fource_cohort_patients_ndx on fource_cohort_patients(patient_num);
--------------------------------------------------------------------------------
-- Add diagnoses (ICD9) going back 365 days from admission ** JK
--------------------------------------------------------------------------------
begin
TM_LOG_PKG.log_msg( -222,'Step18 Load fource_observations Rows Start ', 'X'); 
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
 	from i2b2_user.observation_fact f --with (nolock)
		inner join fource_cohort_patients p 
			on f.patient_num=p.patient_num
				--and cast(trunc(f.start_date) as date) between dateadd(dd,@lookback_days,p.admission_date) and p.source_data_updated_date
                and trunc(f.start_date) between trunc(p.admission_date)-365 and trunc(p.source_data_updated_date)
	where f.concept_cd like ( select code_prefix_icd9cm || '%' from fource_config where rownum = 1 );-- and code_prefix_icd9cm <>'';
TM_LOG_PKG.log_msg( -222,'Step18 Load fource_observations Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;
/

--------------------------------------------------------------------------------
-- Add diagnoses (ICD10) going back 365 days
--------------------------------------------------------------------------------


begin
TM_LOG_PKG.log_msg( -222,'Step19 Load fource_observations Rows Start ', 'X'); 
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
 	from i2b2_user.observation_fact f --with (nolock)
		inner join fource_cohort_patients p 
			on f.patient_num=p.patient_num 
				--and cast(trunc(f.start_date) as date) between dateadd(dd,@lookback_days,p.admission_date) and p.source_data_updated_date
                and trunc(f.start_date) between trunc(p.admission_date)-365 and trunc(p.source_data_updated_date)
	where f.concept_cd like (select code_prefix_icd10cm || '%' from fource_config where rownum = 1);-- and code_prefix_icd10cm <>'';

TM_LOG_PKG.log_msg( -222,'Step19 Load fource_observations Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;
/

--select count(distinct patient_num) from fource_observations; --293601
--------------------------------------------------------------------------------
-- Add medications (Med Class) going back 365 days
--------------------------------------------------------------------------------


declare

begin
              TM_LOG_PKG.log_msg( -222,'Step20 Load fource_observations Rows  Start ', 'X'); 

for r_data in (  select distinct med_class from tm_cz.fource_med_map   m  ) loop
insert into tm_cz.fource_observations (cohort, patient_num, severe, concept_type, concept_code, calendar_date, days_since_admission, value, logvalue)
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
		inner join i2b2_user.observation_fact f --with (nolock)
			on f.concept_cd = m.local_med_code
		inner join fource_cohort_patients p 
			on f.patient_num=p.patient_num 
            and m.med_class = r_data.med_class
            and trunc(f.start_date) between trunc(p.admission_date)-365 and trunc(p.source_data_updated_date) 
             and modifier_cd ='@'  ;

               TM_LOG_PKG.log_msg( -222,'Step20-1 Load fource_observations Rows '||sql%rowcount||' End ', 'X'); 
commit;
end loop;
commit;
              TM_LOG_PKG.log_msg( -222,'Step20 Load fource_observations Rows  End ', 'X'); 
end;
/

--and cast(trunc(f.start_date) as date) between dateadd(dd,@lookback_days,p.admission_date) and p.source_data_updated_date

--------------------------------------------------------------------------------
-- Add labs (LOINC) going back 60 days (two months)
--------------------------------------------------------------------------------

declare

begin
   TM_LOG_PKG.log_msg( -222,'Step21 Load fource_observations Rows  Start ', 'X'); 
for r_data in ( select distinct local_lab_code from fource_lab_map  ) loop
--for r_data in ( select distinct patient_num from fource_cohort_patients fcp  ) loop

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
		inner join i2b2_user.observation_fact f --with (nolock)
			on f.concept_cd=l.local_lab_code and nvl(nullif(f.units_cd,''),'DEFAULT')=l.local_lab_units
		inner join fource_cohort_patients p 
			on f.patient_num=p.patient_num
	where l.local_lab_code is not null
		and f.nval_num is not null
        and f.concept_cd = r_data.local_lab_code
		and f.nval_num >= 0
		and trunc(f.start_date) between trunc(p.admission_date)-60 and trunc(p.source_data_updated_date) --@lab lookback days
	group by p.cohort, p.patient_num, p.severe, p.admission_date, trunc(f.start_date), l.fource_loinc;


               TM_LOG_PKG.log_msg( -222,'Step21-1 Load fource_observations Rows '||sql%rowcount||' End ', 'X'); 
commit;
end loop;
commit;
              TM_LOG_PKG.log_msg( -222,'Step21 Load fource_observations Rows  End ', 'X'); 
end;
/
--------------------------------------------------------------------------------
-- Add procedures (Proc Groups) going back 365 days  before this is running
--------------------------------------------------------------------------------

set serveroutput on

begin
 TM_LOG_PKG.log_msg( -222,'Step22 Load fource_observations Rows  Start ', 'X'); 
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
		inner join i2b2_user.observation_fact f --with (nolock)
			on f.concept_cd = x.local_proc_code
		inner join fource_cohort_patients p 
			on f.patient_num=p.patient_num 
	where x.local_proc_code is not null
    --and p.patient_num= v_patient_num
    --and f.concept_cd = r_data.local_proc_code
    and trunc(f.start_date) between trunc(p.admission_date)-365 and trunc(p.source_data_updated_date);
    
               TM_LOG_PKG.log_msg( -222,'Step22-1 Load fource_observations Rows '||sql%rowcount||' End ', 'X'); 
commit;
end loop;
commit;
              TM_LOG_PKG.log_msg( -222,'Step22 Load fource_observations Rows  End ', 'X'); 
end;
/
--------------------------------------------------------------------------------
-- Flag observations that contribute to the disease severity definition 
--------------------------------------------------------------------------------
--test select * from fource_observations where concept_code = 'ARDS';
begin
  TM_LOG_PKG.log_msg( -222,'Step23 Load fource_observations Rows  Start ', 'X'); 
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

              TM_LOG_PKG.log_msg( -222,'Step23-1 Load fource_observations Rows '||sql%rowcount||' End ', 'X'); 
commit;
end loop;
commit;
              TM_LOG_PKG.log_msg( -222,'Step23 Load fource_observations Rows  End ', 'X'); 
end;
/


--******************************************************************************
--******************************************************************************
--*** Determine which patients had severe disease or died
--******************************************************************************
--******************************************************************************


--------------------------------------------------------------------------------
-- Flag the patients who had severe disease with 30 days of admission.
--------------------------------------------------------------------------------
--test select * from fource_cohort_patients where severe = 0;

begin
              TM_LOG_PKG.log_msg( -222,'Step24 Load fource_cohort_patients Rows Start ', 'X'); 
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
              TM_LOG_PKG.log_msg( -222,'Step24 Load fource_cohort_patients Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;
/
-- Flag the severe patients in the observations table


begin
              TM_LOG_PKG.log_msg( -222,'Step25 Load fource_observations Rows Start ', 'X'); 
update fource_observations f
set f.severe=1
where exists(select patient_num,cohort
	     from fource_cohort_patients c where c.severe=0 and 
f.patient_num = c.patient_num and f.cohort = c.cohort );

              TM_LOG_PKG.log_msg( -222,'Step25 Load fource_observations Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;
/
--------------------------------------------------------------------------------
-- Add death dates to patients who have died.
--------------------------------------------------------------------------------
--if exists (select * from fource_config where death_data_available = 1)
--begin;
	-- Add the original death date.

begin

 TM_LOG_PKG.log_msg( -222,'Step26 Load fource_observations Rows Start ', 'X');
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


	-- Make sure the death date is not after the source data updated date
	update fource_cohort_patients
		set death_date = null
		where death_date > source_data_updated_date
        and (select death_data_available from fource_config where rownum = 1)= 1;

              TM_LOG_PKG.log_msg( -222,'Step26 Load fource_observations Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;
/
--******************************************************************************
--******************************************************************************
--*** For each cohort, create a list of dates since the first case.
--******************************************************************************
--******************************************************************************

  truncate table fource_date_list ;
begin
              TM_LOG_PKG.log_msg( -222,'Step27 Load fource_observations Rows Start ', 'X'); 
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
              TM_LOG_PKG.log_msg( -222,'Step27 Load fource_observations Rows '||sql%rowcount||' End ', 'X'); 
commit;
end;
/
truncate table fource_LocalPatClinicalCourse drop storage;
begin
              TM_LOG_PKG.log_msg( -222,'Step28 Load fource_LocalPatClinicalCourse Rows Start ', 'X'); 

for r_data in ( select distinct cohort,patient_num from fource_cohort_patients ) loop
insert into fource_LocalPatClinicalCourse 
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
            where p.cohort = r_data.cohort
            and p.patient_num = r_data.patient_num
	group by p.cohort, p.patient_num, p.admission_date, d.d;
commit; -- 5 minutes  
              TM_LOG_PKG.log_msg( -222,'Step28-1 Load fource_LocalPatClinicalCourse  End '|| r_data.cohort, 'X'); 
end loop;
commit;
              TM_LOG_PKG.log_msg( -222,'Step28 Load fource_LocalPatClinicalCourse Rows End ', 'X'); 
end; 
/

-- Flag the days when the patients was in the hospital
begin
              TM_LOG_PKG.log_msg( -222,'Step29 Load fource_LocalPatClinicalCourse Start ', 'X'); 
merge into fource_LocalPatClinicalCourse p
	using (
    select distinct p.patient_num,  p.calendar_date
    from fource_LocalPatClinicalCourse p 
    inner join fource_admissions a on a.patient_num = p.patient_num
        and trunc(a.admission_date)>= trunc(p.calendar_date)-days_since_admission --TODO: Check the logic again - MICHELE IS THE SUBTRACTION CORRECT
		and trunc(a.admission_date)<=trunc(p.calendar_date)
		and a.discharge_date>=trunc(p.calendar_date) 
        )d
    on (d.patient_num=p.patient_num and d.calendar_date=p.calendar_date)
    when matched then
        update set p.in_hospital=1;
        
              TM_LOG_PKG.log_msg( -222,'Step29 Load fource_LocalPatClinicalCourse Rows End ', 'X');        
commit;
end;
/
-- Flag the days when the patient was in the ICU, making sure the patient was also in the hospital on those days
begin
TM_LOG_PKG.log_msg( -222,'Step30 Load fource_LocalPatClinicalCourse Rows Start', 'X'); 
merge into fource_LocalPatClinicalCourse p
    using ( 
    --with pt_icu as (
    select patient_num,  calendar_date, in_hospital, in_icu from (
    select distinct p.patient_num,  p.calendar_date, p.in_hospital, p.in_icu
            from fource_LocalPatClinicalCourse p
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

TM_LOG_PKG.log_msg( -222,'Step30 Load fource_LocalPatClinicalCourse Rows End '||sql%rowcount, 'X'); 
commit;
end;
/

truncate table fource_LocalPatientSummary ;
begin
TM_LOG_PKG.log_msg( -222,'Step31 Load fource_LocalPatientSummary Rows Start', 'X'); 
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
		left outer join i2b2_user.patient_dimension p
			on p.patient_num=c.patient_num
		left outer join fource_code_map m
			on p.sex_cd = m.local_code
				and m.code in ('sex_patient:male','sex_patient:female');
               
TM_LOG_PKG.log_msg( -222,'Step31 Load fource_LocalPatientSummary Rows End '||sql%rowcount, 'X'); 
commit;
end;
/

begin
TM_LOG_PKG.log_msg( -222, 'Step32 Merge fource_LocalPatientSummary Start ', 'X');
merge into fource_LocalPatientSummary s
using (select p.sex, p.patient_num
	   from fource_LocalPatientSummary s
		inner join (
			select patient_num, (case when male=1 then 'male' else 'female' end) sex
			from (
				select patient_num,
					max(case when m.code='sex_fact:male' then 1 else 0 end) male,
					max(case when m.code='sex_fact:female' then 1 else 0 end) female
				from i2b2_user.observation_fact f --with (nolock)
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
     TM_LOG_PKG.log_msg( -222, 'Step32 Merge fource_LocalPatientSummary End '||sql%rowcount, 'X');               
commit;
TM_LOG_PKG.log_msg( -222, 'Step32 Merge fource_LocalPatientSummary End ', 'X');

end;
/



-- Get the last discharge date and whether the patient is still in the hospital as of the source_data_updated_date.

begin
TM_LOG_PKG.log_msg( -222, 'Step33 Merge fource_LocalPatientSummary Start ', 'X');
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
     TM_LOG_PKG.log_msg( -222, 'Step33 Merge fource_LocalPatientSummary End '||sql%rowcount, 'X');               
commit;
TM_LOG_PKG.log_msg( -222, 'Step33 Merge fource_LocalPatientSummary End ', 'X');

end;
/

--select * from fource_LocalPatClinicalCourse where in_icu = 1;
-- Get earliest ICU date for patients who were in the ICU.
begin
TM_LOG_PKG.log_msg( -222, 'Step34 Merge fource_LocalPatientSummary Start ', 'X');
merge into fource_LocalPatientSummary s
      using (
			select cohort, patient_num, min(calendar_date) icu_date
					from fource_LocalPatClinicalCourse
					where in_icu=1
					group by cohort, patient_num
			) x
        on (s.cohort=x.cohort and s.patient_num=x.patient_num and (select icu_data_available from fource_config where rownum = 1)=1)
        when matched then
        update set s.icu_date = x.icu_date,
                   s.icu = 1;
     TM_LOG_PKG.log_msg( -222, 'Step34 Merge fource_LocalPatientSummary End '||sql%rowcount, 'X');               
commit;
TM_LOG_PKG.log_msg( -222, 'Step34 Merge fource_LocalPatientSummary End ', 'X');

end;
/

--------------------------------------------------------------------------------
-- LocalPatientObservations: Diagnoses, procedures, medications, and labs
--------------------------------------------------------------------------------
 truncate table fource_LocalPatObservations;
begin
TM_LOG_PKG.log_msg( -222, 'Step35 Merge fource_LocalPatObservations Start ', 'X');
insert into fource_LocalPatObservations
	select (select siteid from fource_config where rownum = 1), 
    cohort, patient_num, days_since_admission, concept_type, concept_code, value
	from fource_observations;
    
     TM_LOG_PKG.log_msg( -222, 'Step35  Merge fource_LocalPatObservations End '||sql%rowcount, 'X');               
commit;
TM_LOG_PKG.log_msg( -222, 'Step35  Merge fource_LocalPatObservations End ', 'X');

end;
/
--------------------------------------------------------------------------------
-- LocalPatientRace: local and 4CE race code(s) for each patient
--------------------------------------------------------------------------------
truncate  table fource_LocalPatientRace;

begin
    TM_LOG_PKG.log_msg( -222, 'Step36  Merge fource_LocalPatientRace Start', 'X'); 
insert into fource_LocalPatientRace
		select distinct (select siteid from fource_config where rownum = 1) siteid, cohort, patient_num, race_local_code, race_4ce
		from (
			-- Race from the patient_dimension table
			select c.cohort, c.patient_num, m.local_code race_local_code, substr(m.code,14,999) race_4ce
				from fource_cohort_patients c
					inner join i2b2_user.patient_dimension p
						on p.patient_num=c.patient_num
					inner join fource_code_map m
						on p.race_cd = m.local_code
							and m.code like 'race_patient:%'
			union all
			-- Race from the observation_fact. table
			select c.cohort, c.patient_num, m.local_code race_local_code, substr(m.code,11,999) race_4ce
				from fource_cohort_patients c
					inner join i2b2_user.observation_fact p --with (nolock)
						on p.patient_num=c.patient_num
					inner join fource_code_map m
						on p.concept_cd = m.local_code
							and m.code like 'race_fact:%'
		) t
        where ( select race_data_available from fource_config where rownum =1 )=1;

    TM_LOG_PKG.log_msg( -222, 'Step36  Merge fource_LocalPatientRace End', 'X'); 
commit;
end;
/

 truncate table fource_LocalCohorts;
begin
TM_LOG_PKG.log_msg( -222, 'Step37 Merge fource_LocalCohorts Start', 'X'); 
insert into fource_LocalCohorts
	select (select siteid from fource_config where rownum = 1) siteid, cohort, include_in_phase1, include_in_phase2, source_data_updated_date, earliest_adm_date, latest_adm_date 
	from fource_cohort_config;
    TM_LOG_PKG.log_msg( -222, 'Step37 Merge fource_LocalCohorts End', 'X'); 
commit;
end;
/

--------------------------------------------------------------------------------
-- LocalDailyCounts
--------------------------------------------------------------------------------
 truncate table fource_LocalDailyCounts;
-- Get daily counts, except for ICU

begin
     TM_LOG_PKG.log_msg( -222, 'Step38 Merge fource_LocalDailyCounts Start', 'X');   
     
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
		cross join fource_LocalPatClinicalCourse c
	group by cohort, calendar_date, icu_data_available, death_data_available;
    
     TM_LOG_PKG.log_msg( -222,'Step38-1 Merge fource_LocalDailyCounts End '||sql%rowcount, 'X');               
commit;
TM_LOG_PKG.log_msg( -222, 'Step38 Merge fource_LocalDailyCounts End ', 'X');

end;
/

    
    

--------------------------------------------------------------------------------
-- LocalClinicalCourse
--------------------------------------------------------------------------------
  truncate table fource_LocalClinicalCourse ;

begin
TM_LOG_PKG.log_msg( -222, 'Step39 Merge fource_LocalClinicalCourse S ', 'X');
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
		cross join fource_LocalPatClinicalCourse c
		inner join fource_cohort_patients p
			on c.cohort=p.cohort and c.patient_num=p.patient_num
	group by c.cohort, c.days_since_admission, icu_data_available, death_data_available;
     TM_LOG_PKG.log_msg( -222, 'Step39 Merge fource_LocalClinicalCourse End '||sql%rowcount, 'X');               
commit;
TM_LOG_PKG.log_msg( -222, 'Step39 Merge fource_LocalClinicalCourse End ', 'X');

end;
/
--------------------------------------------------------------------------------
-- LocalAgeSex
--------------------------------------------------------------------------------

truncate table fource_LocalAgeSex;
begin
TM_LOG_PKG.log_msg( -222, 'Step39 Merge fource_LocalAgeSex Start ', 'X');
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
     TM_LOG_PKG.log_msg( -222, 'Step39-1 Merge fource_LocalAgeSex End '||sql%rowcount, 'X');               
commit;
TM_LOG_PKG.log_msg( -222, 'Step39 Merge fource_LocalAgeSex End ', 'X');

end;
/
--------------------------------------------------------------------------------
-- LocalLabs
--------------------------------------------------------------------------------

 truncate table fource_LocalLabs;
begin
TM_LOG_PKG.log_msg( -222, 'Step40 Merge fource_LocalLabs Start ', 'X');
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
    
     TM_LOG_PKG.log_msg( -222, 'Step40-1 Merge fource_LocalLabs End '||sql%rowcount, 'X');               
commit;
TM_LOG_PKG.log_msg( -222, 'Step40 Merge fource_LocalLabs End ', 'X');

end;
/

--------------------------------------------------------------------------------
-- LocalDiagProcMed
--------------------------------------------------------------------------------

truncate table fource_LocalDiagProcMed ;

begin
TM_LOG_PKG.log_msg( -222, 'Step41 Merge fource_LocalDiagProcMed Start ', 'X');
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

     TM_LOG_PKG.log_msg( -222, 'Step41-1 Merge fource_LocalDiagProcMed End '||sql%rowcount, 'X');               
commit;
TM_LOG_PKG.log_msg( -222, 'Step41 Merge fource_LocalDiagProcMed End ', 'X');

end;
/


--------------------------------------------------------------------------------
-- LocalRaceByLocalCode
--------------------------------------------------------------------------------
truncate table fource_LocalRaceByLocalCode ;
begin
TM_LOG_PKG.log_msg( -222, 'Step42 Merge fource_LocalRaceByLocalCode Start ', 'X');
insert into fource_LocalRaceByLocalCode
	select (select siteid from fource_config where rownum = 1), r.cohort, r.race_local_code, r.race_4ce, count(*), sum(p.severe)
	from fource_LocalPatientRace r
		inner join fource_cohort_patients p
			on r.cohort=p.cohort and r.patient_num=p.patient_num
	group by r.cohort, r.race_local_code, r.race_4ce;
     TM_LOG_PKG.log_msg( -222, 'Step42-1 Merge fource_LocalRaceByLocalCode End '||sql%rowcount, 'X');               
commit;
TM_LOG_PKG.log_msg( -222, 'Step42 Merge fource_LocalRaceByLocalCode End ', 'X');

end;
/


--------------------------------------------------------------------------------
-- LocalRaceBy4CECode
--------------------------------------------------------------------------------

truncate table fource_LocalRaceBy4CECode;
 begin
 TM_LOG_PKG.log_msg( -222,'Step43 Merge fource_LocalRaceBy4CECode Start ', 'X');
 insert into fource_LocalRaceBy4CECode
	select (select siteid from fource_config where rownum = 1), r.cohort, r.race_4ce, count(*), sum(p.severe)
	from fource_LocalPatientRace r
		inner join fource_cohort_patients p
			on r.cohort=p.cohort and r.patient_num=p.patient_num
	group by r.cohort, r.race_4ce;
     TM_LOG_PKG.log_msg( -222, 'Step43-1 Merge fource_LocalRaceBy4CECode End '||sql%rowcount, 'X');               
commit;
TM_LOG_PKG.log_msg( -222, 'Step43 Merge fource_LocalRaceBy4CECode End ', 'X');

end;
/

--------------------------------------------------------------------------------
-- Cohorts
-------------------------------------------------------------------------------

truncate table fource_Cohorts;

begin
TM_LOG_PKG.log_msg( -222,'Step44 Load fource_Cohorts  Start ', 'X');
insert into fource_Cohorts
	select (select siteid from fource_config where rownum = 1), cohort, source_data_updated_date, earliest_adm_date, latest_adm_date 
	from fource_cohort_config
	where include_in_phase1=1;
TM_LOG_PKG.log_msg( -222,'Step44 Load fource_Cohorts  End ', 'X');

commit;

end;
/
--------------------------------------------------------------------------------
-- DailyCounts
--------------------------------------------------------------------------------
--drop table fource_DailyCounts;

 truncate table fource_DailyCounts ;
begin
TM_LOG_PKG.log_msg( -222,'Step45 Load fource_DailyCounts  Start ', 'X');
insert into fource_DailyCounts 
	select *
	from fource_LocalDailyCounts
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);
TM_LOG_PKG.log_msg( -222,'Step45 Load fource_DailyCounts  End ', 'X');

commit;

end;
/

--------------------------------------------------------------------------------
-- ClinicalCourse
--------------------------------------------------------------------------------

 truncate table fource_ClinicalCourse;
begin
TM_LOG_PKG.log_msg( -222,'Step46 Load fource_ClinicalCourse  Start ', 'X');
insert into fource_ClinicalCourse 
	select * 
	from fource_LocalClinicalCourse
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);
TM_LOG_PKG.log_msg( -222,'Step46 Load fource_ClinicalCourse  End ', 'X');

commit;

end;
/
--------------------------------------------------------------------------------
-- AgeSex
--------------------------------------------------------------------------------

truncate table fource_AgeSex ;
begin
TM_LOG_PKG.log_msg( -222,'Step47 Load fource_AgeSex  Start ', 'X');
insert into fource_AgeSex 
	select * 
	from fource_LocalAgeSex
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);
TM_LOG_PKG.log_msg( -222,'Step47 Load fource_AgeSex  End ', 'X');

commit;

end;
/
--------------------------------------------------------------------------------
-- Labs
--------------------------------------------------------------------------------

truncate table fource_Labs;
begin
TM_LOG_PKG.log_msg( -222,'Step48 Load fource_Labs  Start ', 'X');
insert into fource_Labs 
	select * 
	from fource_LocalLabs
	where cohort in ( select cohort from fource_cohort_config where include_in_phase1=1 );

TM_LOG_PKG.log_msg( -222,'Step48 Load fource_Labs  End ', 'X');

commit;

end;
/
--------------------------------------------------------------------------------
-- DiagProcMed
--------------------------------------------------------------------------------

truncate table fource_DiagProcMed;
begin
TM_LOG_PKG.log_msg( -222,'Step49 Load fource_DiagProcMed  Start ', 'X');
insert into fource_DiagProcMed 
	select * 
	from fource_LocalDiagProcMed
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);

TM_LOG_PKG.log_msg( -222,'Step49 Load fource_DiagProcMed  End ', 'X');

commit;

end;
/

--------------------------------------------------------------------------------
-- RaceByLocalCode
--------------------------------------------------------------------------------

 truncate table fource_RaceByLocalCode;
 
 begin
 TM_LOG_PKG.log_msg( -222,'Step50 Load fource_RaceByLocalCode  Start ', 'X');
insert into fource_RaceByLocalCode 
	select * 
	from fource_LocalRaceByLocalCode
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);

TM_LOG_PKG.log_msg( -222,'Step50 Load fource_RaceByLocalCode  End ', 'X');

commit;

end;
/

--------------------------------------------------------------------------------
-- RaceBy4CECode
--------------------------------------------------------------------------------

truncate table fource_RaceBy4CECode ;
begin

TM_LOG_PKG.log_msg( -222,'Step51 Load fource_RaceBy4CECode  Start ', 'X');
insert into fource_RaceBy4CECode 
	select * 
	from fource_LocalRaceBy4CECode
	where cohort in (select cohort from fource_cohort_config where include_in_phase1=1);

TM_LOG_PKG.log_msg( -222,'Step51 Load fource_RaceBy4CECode  End ', 'X');

commit;

end;
/
--------------------------------------------------------------------------------
-- LabCodes
--------------------------------------------------------------------------------
truncate  table fource_LabCodes;

begin
TM_LOG_PKG.log_msg( -222,'Step52 Load fource_LabCodes  Start ', 'X');
insert into fource_LabCodes
	select (select siteid from fource_config where rownum = 1), fource_loinc, fource_lab_units, fource_lab_name, scale_factor, replace(local_lab_code,',',';'), replace(local_lab_units,',',';'), replace(local_lab_name,',',';'), replace(notes,',',';')
	from fource_lab_map_report;

TM_LOG_PKG.log_msg( -222,'Step52 Load fource_LabCodes  End ', 'X');

commit;

end;
/
begin

TM_LOG_PKG.log_msg( -222,'Step53 Load   Start ', 'X');
delete from fource_LabCodes
where scale_factor = 0 ;

commit;

delete from fource_LocalPatClinicalCourse where in_hospital=0 and severe=0 and in_icu=0 and dead=0;

commit;
TM_LOG_PKG.log_msg( -222,'Step53 Load   End ', 'X');
end;
/
truncate table fource_LocalPatientMapping ;
  
begin

TM_LOG_PKG.log_msg( -222,'Step54 Load   Start ', 'X');        
insert into fource_LocalPatientMapping (siteid, patient_num, study_num)   
 select  (select siteid from fource_config where   rownum = 1),patient_num,patient_num from ( select distinct patient_num
			from fource_LocalPatientSummary) where (select replace_patient_num from fource_config where  rownum = 1) = 1;
commit;

TM_LOG_PKG.log_msg( -222,'Step54 Load   End ', 'X');

commit;

end;
/

