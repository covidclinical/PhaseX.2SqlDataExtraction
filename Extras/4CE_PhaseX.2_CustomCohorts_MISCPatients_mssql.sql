--------------------------------------------------------------------------------
-- Custom cohorts: All MISC patients
-- Database: Microsoft SQL Server
-- Data Model: i2b2
-- Created By: Griffin Weber (weber@hms.harvard.edu)
--
-- This code creates a cohort capturing all patients in the #fource_misc table.
--
-- Instructions: Search the 4CE_PhaseX.2_Files_*.sql script for the comment
-- "Add additional custom cohorts here". Right below it insert the contents of
-- this script. If you use a custom database schema, replace "dbo." with the 
-- schema name. If you use multiple fact table, adjust the SQL queries as
-- needed. The first two lines of code delete all existing cohorts and patients.
-- The output of the script, therefore, will just be the one MISC cohort.
-- Comment out those lines to leave the existing cohorts and make a MISC cohort
-- containing only the MISC patients who are not in other cohorts.
--------------------------------------------------------------------------------

-- *** Delete all existing cohorts and patients ***
delete from #fource_cohort_config
delete from #fource_cohort_patients

-- Get admissions for MISC patients
insert into #fource_admissions
	select *
	from (
		select distinct patient_num, cast(start_date as date) admission_date, isnull(cast(end_date as date),'1/1/2199') discharge_date
		from (
			select patient_num, start_date, end_date
				from dbo.visit_dimension
				where inout_cd in (select local_code from #fource_code_map where code = 'inpatient_inout_cd')
			union all
			select patient_num, start_date, end_date
				from dbo.visit_dimension v
				where location_cd in (select local_code from #fource_code_map where code = 'inpatient_location_cd')
			union all
			select f.patient_num, f.start_date, isnull(f.end_date,v.end_date)
				from dbo.observation_fact f
					inner join dbo.visit_dimension v
						on v.encounter_num=f.encounter_num and v.patient_num=f.patient_num
				where f.concept_cd in (select local_code from #fource_code_map where code = 'inpatient_concept_cd')
		) t
	) t
	where (admission_date >= '1/1/2016') and (discharge_date >= admission_date)
		and patient_num not in (select patient_num from #fource_cohort_patients)
		and patient_num in (select patient_num from #fource_misc)

-- Get ICU dates for MISC patients
insert into #fource_icu
	select *
	from (
		select distinct patient_num, cast(start_date as date) start_date, isnull(cast(end_date as date),'1/1/2199') end_date
		from (
			select patient_num, start_date, end_date
				from dbo.visit_dimension
				where inout_cd in (select local_code from #fource_code_map where code = 'icu_inout_cd')
			union all
			select patient_num, start_date, end_date
				from dbo.visit_dimension v
				where location_cd in (select local_code from #fource_code_map where code = 'icu_location_cd')
			union all
			select f.patient_num, f.start_date, isnull(f.end_date,v.end_date)
				from dbo.observation_fact f
					inner join dbo.visit_dimension v
						on v.encounter_num=f.encounter_num and v.patient_num=f.patient_num
				where f.concept_cd in (select local_code from #fource_code_map where code = 'icu_concept_cd')
		) t
	) t
	where (start_date >= '1/1/2016') and (end_date >= start_date)
		and patient_num not in (select patient_num from #fource_cohort_patients)
		and patient_num in (select patient_num from #fource_misc)

-- Add death dates for MISC patients
insert into #fource_death
	select patient_num, isnull(death_date,'1/1/1900') 
	from dbo.patient_dimension
	where (death_date is not null or vital_status_cd in ('Y'))
		and patient_num not in (select patient_num from #fource_cohort_patients)
		and death_date >= '1/1/2016'
		and patient_num in (select patient_num from #fource_misc)

-- Define the cohort
;with t as (
	select '1/1/2017' start_date, isnull(source_data_updated_date,GetDate()) end_date
	from #fource_config
)
insert into #fource_cohort_config
	select 'MISC', 1, 1, end_date, start_date, end_date from t

-- Get the MISC patients, using the misc_date as the index date
insert into #fource_cohort_patients
	select c.cohort, m.patient_num, min(m.misc_date), c.source_data_updated_date, 0, null, null
	from #fource_misc m
		inner join #fource_cohort_config c
			on m.misc_date >= c.earliest_adm_date and m.misc_date <= c.latest_adm_date
	where c.cohort='MISC'
		and m.patient_num not in (select patient_num from #fource_cohort_patients)
	group by c.cohort, m.patient_num, c.source_data_updated_date

