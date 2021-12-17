#!/bin/bash
sudo docker cp ./ClinicalCourse-BCH.csv	 5817dc8b00b9:/4ceData/Input/4ce_2.1_extendedForAKI/ClinicalCourse-BCH.csv
sudo docker cp ./DailyCounts-BCH.csv	 5817dc8b00b9:/4ceData/Input/4ce_2.1_extendedForAKI/DailyCounts-BCH.csv
sudo docker cp ./Demographics-BCH.csv	 5817dc8b00b9:/4ceData/Input/4ce_2.1_extendedForAKI/Demographics-BCH.csv
sudo docker cp ./Diagnoses-BCH.csv	 5817dc8b00b9:/4ceData/Input/4ce_2.1_extendedForAKI/Diagnoses-BCH.csv
sudo docker cp ./Labs-BCH.csv	 5817dc8b00b9:/4ceData/Input/4ce_2.1_extendedForAKI/Labs-BCH.csv
sudo docker cp ./LocalPatientClinicalCourse.csv	 5817dc8b00b9:/4ceData/Input/4ce_2.1_extendedForAKI/LocalPatientClinicalCourse.csv
sudo docker cp ./LocalPatientMapping.csv	 5817dc8b00b9:/4ceData/Input/4ce_2.1_extendedForAKI/LocalPatientMapping.csv
sudo docker cp ./LocalPatientObservations.csv	 5817dc8b00b9:/4ceData/Input/4ce_2.1_extendedForAKI/LocalPatientObservations.csv
sudo docker cp ./LocalPatientSummary.csv	 5817dc8b00b9:/4ceData/Input/4ce_2.1_extendedForAKI/LocalPatientSummary.csv
sudo docker cp ./Medications-BCH.csv	 5817dc8b00b9:/4ceData/Input/4ce_2.1_extendedForAKI/Medications-BCH.csv

sudo docker exec -it 5817dc8b00b9 bash chmod_csv.sh

