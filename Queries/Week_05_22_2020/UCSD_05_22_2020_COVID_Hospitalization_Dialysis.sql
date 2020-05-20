/************************************************************************************************************
Project:	R2D2
Create date: 05/20/2020
Query: (1A) What is the all-cause mortality of hospitalized, African-American patients 
			vs all other patients of other racial groups?

		(1B) For hospitalized COVID patients who are not admitted to ICU during their stay,
		how many come back to the ED or hospitalized within 7 days of discharge?

		(1C) For hospitalzed COVID patients who were not dialysis dependent prior to hospitalization,
		how many of them required inpatient dialysis?

*************************************************************************************************************/



/************************************************************************************************************* 
	Site specific customization required
**************************************************************************************************************/

	-- COVID patients 
	if object_id('tempdb.dbo.#covid_pos') is  not null drop table #covid_pos 
	select subject_id [person_id], cohort_start_date, cohort_end_date
	into #covid_pos 
	from omop_v5.OMOP5.cohort
	where cohort_definition_id = 100200	---UCSD COVID-19 CONFIRMED POSITIVE REGISTRY


	--write code identifying COVID patients with + lab tests



	--ICU departments 
	if object_id('tempdb.dbo.#icu_departments') is  not null drop table #icu_departments 
	select cs.care_site_id, cs.care_site_name
	into #icu_departments 
	from OMOP5.care_site cs 
	join CDWRPROD_Clarity.dbo.clarity_dep dep on dep.department_id = cs.DEPARTMENT_ID
	where dep.department_id in (
		 700203	--HC 2-SICU
		,700204	--HC 2-ISCC
		,700503	--HC 5-BURN ICU
		,710203	--TH 2-CVICU
		,710303	--SC 3A-ICU
		,710310	--JM 3F-ICU
		,710311	--JM 3G-ICU
		,710312	--JM 3H-ICU
		,710810	--JM 8-NICU
	)

	select * from #icu_departments


	if object_id('tempdb.dbo.#dialysis') is  not null drop table #dialysis  
	select * 
	into #dialysis
	from OMOP_Vocabulary.vocab_51.concept c
	where c.concept_id in (
	2213597
	, 45889335
	, 2213572
	, 2213573
	, 2213601
	, 1314323
	, 1314324
	, 4032243
	, 762572
	, 4120120
	, 2002282
	, 40313125
	, 40313128
	, 40348035
	, 40350725
	, 40513647
	, 45889034
	, 45889365
)



/*************************************************************************************************************  
Query: (1A) What is the all-cause mortality of hospitalized, African-American patients 
			vs all other patients of other racial groups?
*************************************************************************************************************/


--Hospitalizations with race
if object_id('tempdb.dbo.#hsp_mortality') is  not null drop table #hsp_mortality 
select distinct p.person_id, p.race_concept_id, p.race_source_value, d.death_datetime
, vo.visit_start_datetime, vo.visit_end_datetime, vo.discharge_to_concept_id, vo.discharge_to_source_value 
, case when d.death_date between vo.visit_start_datetime and vo.visit_end_datetime
	or discharge_to_concept_id = 44814686 -- Deceased
	then 1 else NULL end as [Hospital_mortality]
, case when p.race_concept_id = 8516	--Black or African American
	then 1 else NULL end as [African_American]
into #hsp_mortality
from --#covid_pos cp
--join 
omop_v5.OMOP5.visit_occurrence vo --on vo.person_id = cp.person_id
left join OMOP_v5.omop5.person p on p.person_id = vo.person_id
left join OMOP_v5.OMOP5.death d on d.person_id = vo.person_id
where vo.visit_concept_id in (9201, 262, 9203) -- IP, EI, ED visits 

--Numerator
select count(distinct person_id) from #hsp_mortality where [Hospital_mortality] = 1 and African_American = 1

--Denominator
select count(distinct person_id) from #hsp_mortality where [Hospital_mortality] = 1 


--select distinct discharge_to_concept_id, discharge_to_source_value from #hsp_mortality 
-- select distinct race_concept_id, race_source_value from #hsp_mortality 




/**************************************************************************************************************
(1B) For hospitalized COVID patients who are not admitted to ICU during their stay,
		how many come back to the ED or hospitalized within 7 days of discharge?

*************************************************************************************************************/


	--ICU admissions of COVID patients 
	if object_id('tempdb.dbo.#ICU_transfers') is  not null drop table #ICU_transfers 
	select distinct vd.visit_occurrence_id, visit_detail_id, vd.person_id, visit_detail_concept_id
	, visit_detail_start_datetime, visit_detail_end_datetime
	, vd.care_site_id, icu.care_site_name
	into #ICU_transfers
	from #covid_pos cp 
	join OMOP5.visit_occurrence vo on vo.person_id = cp.person_id
	join omop5.visit_detail vd on  vo.visit_occurrence_id = vd.visit_occurrence_id
	join #icu_departments icu on icu.care_site_id = vd.care_site_id
	where vo.visit_concept_id in (9201, 262, 9203) -- IP, EI, ED visits 

	select * from #ICU_transfers


--COVID hsp patients not in ICU
if object_id('tempdb.dbo.#Readmissions') is  not null drop table #Readmissions 
select distinct vo.visit_occurrence_id, vo.person_id, vo.visit_concept_id, vo.visit_start_datetime, vo.visit_end_datetime
,readm.visit_concept_id Readm_visit_concept_id, readm.visit_start_datetime readm_visit_start_datetime, readm.visit_end_datetime readm_visit_end_datetime
into #Readmissions
from #covid_pos cp 
join OMOP5.visit_occurrence vo on vo.person_id = cp.person_id
left join #ICU_transfers icu on icu.visit_occurrence_id = vo.visit_occurrence_id
--readmission within 7 days of discharge
left join OMOP5.visit_occurrence readm on readm.person_id = cp.person_id and readm.visit_concept_id in (9201, 262, 9203) -- IP, EI, ED visits 
	and datediff(dd, vo.visit_end_datetime, readm.visit_start_datetime) between 0 and 7
where vo.visit_concept_id in (9201, 262, 9203) -- IP, EI, ED visits 
and icu.visit_occurrence_id is null -- not transferred to the ICU


select * from #Readmissions 



/**************************************************************************************************************
(1C) For hospitalzed COVID patients who were not dialysis dependent prior to hospitalization,
		how many of them required inpatient dialysis?

*************************************************************************************************************/

-- COVID patients with dialysis at any time
if object_id('tempdb.dbo.#dialysis_covid_pats') is  not null drop table #dialysis_covid_pats 
select distinct cp.person_id, cp.cohort_start_date, cp.cohort_end_date
, po.procedure_concept_id, po.procedure_datetime, po.procedure_source_value, po.visit_occurrence_id
, d.*
into #dialysis_covid_pats
from #covid_pos cp 
join OMOP_v5.OMOP5.procedure_occurrence po on cp.person_id = po.person_id
join #dialysis d on d.concept_id = po.procedure_concept_id and d.domain_id = 'Procedure'
union 
select distinct cp.person_id, cp.cohort_start_date, cp.cohort_end_date
, po.observation_concept_id, po.observation_datetime, po.observation_source_value, po.visit_occurrence_id
, d.*
from #covid_pos cp 
join OMOP_v5.OMOP5.observation po on cp.person_id = po.person_id
join #dialysis d on d.concept_id = po.observation_concept_id and d.domain_id = 'observation'

select * from #dialysis_covid_pats 


--select * from #dialysis



--COVID pats w/ no prior dialysis requiring inpatient dialysis
if object_id('tempdb.dbo.#IP_dialysis') is  not null drop table #IP_dialysis 
select distinct  cp.person_id, cp.cohort_start_date, cp.cohort_end_date
, vo.visit_occurrence_id, vo.visit_start_datetime, vo.visit_end_datetime, vo.visit_concept_id
, ipd.procedure_datetime, ipd.procedure_source_value 
into #IP_dialysis
from #covid_pos cp 
join omop_v5.OMOP5.visit_occurrence vo on vo.person_id = cp.person_id
left join #dialysis_covid_pats d on d.person_id = cp.person_id and d.procedure_datetime < vo.visit_start_datetime 
left join #dialysis_covid_pats ipd on ipd.visit_occurrence_id = vo.visit_occurrence_id -- IP dialysis

where vo.visit_concept_id in (9201, 262, 9203) -- IP, EI, ED visits 
and d.person_id is null  -- no prior dialysis
and ipd.visit_occurrence_id is not null 

select * from #IP_dialysis





--- Rough work 
select top 100 * from OMOP5.visit_occurrence where datediff(dd, visit_start_date, getdate())<=14 order by visit_start_date 