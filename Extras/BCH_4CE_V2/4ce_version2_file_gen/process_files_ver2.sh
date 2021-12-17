#/bin/bash
cd /home/jaspreet_khanna/covid_files

sed '/^$/d' DailyCounts.csv.1 > DailyCounts.csv
rm ./DailyCounts.csv.1
sed '/^$/d' ClinicalCourse.csv.1 > ClinicalCourse.csv
rm ./ClinicalCourse.csv.1
sed '/^$/d' AgeSex.csv.1 > AgeSex.csv
rm ./AgeSex.csv.1
sed '/^$/d' Labs.csv.1 > Labs.csv
rm ./Labs.csv.1
sed '/^$/d' DiagProcMed.csv.1 > DiagProcMed.csv
rm ./DiagProcMed.csv.1
sed '/^$/d' RaceByLocalCode.csv.1 > RaceByLocalCode.csv
rm ./RaceByLocalCode.csv.1
sed '/^$/d' RaceBy4CECode.csv.1 > RaceBy4CECode.csv
rm ./RaceBy4CECode.csv.1
sed '/^$/d' LabCodes.csv.1 > LabCodes.csv
rm ./LabCodes.csv.1
sed '/^$/d' LocalDailyCounts.csv.1 > LocalDailyCounts.csv
rm ./LocalDailyCounts.csv.1
sed '/^$/d' LocalClinicalCourse.csv.1 > LocalClinicalCourse.csv
rm ./LocalClinicalCourse.csv.1
sed '/^$/d' LocalAgeSex.csv.1 > LocalAgeSex.csv
rm ./LocalAgeSex.csv.1
sed '/^$/d' LocalLabs.csv.1 > LocalLabs.csv
rm ./LocalLabs.csv.1
sed '/^$/d' LocalDiagProcMed.csv.1 > LocalDiagProcMed.csv
rm ./LocalDiagProcMed.csv.1
sed '/^$/d' LocalRaceByLocalCode.csv.1 > LocalRaceByLocalCode.csv
rm ./LocalRaceByLocalCode.csv.1 
sed '/^$/d' LocalRaceBy4CECode.csv.1 > LocalRaceBy4CECode.csv
rm ./LocalRaceBy4CECode.csv.1
sed '/^$/d' LocalPatientClinicalCourse.csv.1 > LocalPatientClinicalCourse.csv
rm ./LocalPatientClinicalCourse.csv.1
sed '/^$/d' LocalPatientSummary.csv.1 > LocalPatientSummary.csv
rm ./LocalPatientSummary.csv.1
sed '/^$/d' LocalPatientObservations.csv.1 > LocalPatientObservations.csv
rm ./LocalPatientObservations.csv.1
sed '/^$/d' LocalPatientRace.csv.1 > LocalPatientRace.csv
rm ./LocalPatientRace.csv.1
sed '/^$/d' LocalPatientMapping.csv.1 > LocalPatientMapping.csv
rm ./LocalPatientMapping.csv.1

