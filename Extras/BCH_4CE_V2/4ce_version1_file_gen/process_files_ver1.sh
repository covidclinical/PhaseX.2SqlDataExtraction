#/bin/bash
cd /home/jaspreet_khanna/covid_files/scripts_4ce_version1.0/

sed '/^$/d' LocalPatientSummary.csv.1 > LocalPatientSummary.csv
#echo \ >> LocalPatientSummary.csv
rm ./LocalPatientSummary.csv.1

sed '/^$/d' LocalPatientObservations.csv.1 > LocalPatientObservations.csv
#echo \ >> LocalPatientObservations.csv
rm ./LocalPatientObservations.csv.1

sed '/^$/d' LocalPatientClinicalCourse.csv.1 > LocalPatientClinicalCourse.csv
#echo \ >> LocalPatientClinicalCourse.csv
rm ./LocalPatientClinicalCourse.csv.1

sed '/^$/d' LocalPatientMapping.csv.1 > LocalPatientMapping.csv
#echo \ >> LocalPatientMapping.csv
rm ./LocalPatientMapping.csv.1

sed '/^$/d' Labs-BCH.csv.1 > Labs-BCH.csv
#echo \ >> Labs-BCH.csv
rm ./Labs-BCH.csv.1

sed '/^$/d' DailyCounts-BCH.csv.1 > DailyCounts-BCH.csv
#echo \ >> DailyCounts-BCH.csv
rm ./DailyCounts-BCH.csv.1

sed '/^$/d' Demographics-BCH.csv.1 > Demographics-BCH.csv
#echo \ >> Demographics-BCH.csv
rm ./Demographics-BCH.csv.1

sed '/^$/d' Diagnoses-BCH.csv.1 > Diagnoses-BCH.csv
#echo \ >> Diagnoses-BCH.csv
rm ./Diagnoses-BCH.csv.1

sed '/^$/d' Medications-BCH.csv.1 > Medications-BCH.csv
#echo \ >> Medications-BCH.csv
rm ./Medications-BCH.csv.1

sed '/^$/d' ClinicalCourse-BCH.csv.1 > ClinicalCourse-BCH.csv
#echo \ >> ClinicalCourse-BCH.csv
rm ./ClinicalCourse-BCH.csv.1

