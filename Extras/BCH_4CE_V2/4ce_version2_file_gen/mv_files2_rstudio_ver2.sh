#!/bin/bash
			
sudo docker cp ./DailyCounts.csv	5817dc8b00b9:/4ceData/Input/DailyCounts.csv
sudo docker cp ./LocalDailyCounts.csv	5817dc8b00b9:/4ceData/Input/LocalDailyCounts.csv
			
sudo docker cp ./ClinicalCourse.csv	5817dc8b00b9:/4ceData/Input/ClinicalCourse.csv
sudo docker cp ./LocalClinicalCourse.csv	5817dc8b00b9:/4ceData/Input/LocalClinicalCourse.csv
sudo docker cp ./LocalPatientClinicalCourse.csv	5817dc8b00b9:/4ceData/Input/LocalPatientClinicalCourse.csv
			
sudo docker cp ./AgeSex.csv	5817dc8b00b9:/4ceData/Input/AgeSex.csv
sudo docker cp ./LocalAgeSex.csv	5817dc8b00b9:/4ceData/Input/LocalAgeSex.csv
		
sudo docker cp ./Labs.csv	5817dc8b00b9:/4ceData/Input/Labs.csv
sudo docker cp ./LocalLabs.csv	5817dc8b00b9:/4ceData/Input/LocalLabs.csv
sudo docker cp ./LabCodes.csv	5817dc8b00b9:/4ceData/Input/LabCodes.csv
		
sudo docker cp ./DiagProcMed.csv	5817dc8b00b9:/4ceData/Input/DiagProcMed.csv
sudo docker cp ./LocalDiagProcMed.csv	5817dc8b00b9:/4ceData/Input/LocalDiagProcMed.csv
			
sudo docker cp ./RaceByLocalCode.csv	5817dc8b00b9:/4ceData/Input/RaceByLocalCode.csv
sudo docker cp ./LocalRaceByLocalCode.csv	5817dc8b00b9:/4ceData/Input/LocalRaceByLocalCode.csv
			
sudo docker cp ./RaceBy4CECode.csv	5817dc8b00b9:/4ceData/Input/RaceBy4CECode.csv
sudo docker cp ./LocalRaceBy4CECode.csv	5817dc8b00b9:/4ceData/Input/LocalRaceBy4CECode.csv
			
sudo docker cp ./LocalPatientSummary.csv	5817dc8b00b9:/4ceData/Input/LocalPatientSummary.csv
sudo docker cp ./LocalPatientObservations.csv	5817dc8b00b9:/4ceData/Input/LocalPatientObservations.csv
sudo docker cp ./LocalPatientRace.csv	5817dc8b00b9:/4ceData/Input/LocalPatientRace.csv
sudo docker cp ./LocalPatientMapping.csv	5817dc8b00b9:/4ceData/Input/LocalPatientMapping.csv
sudo docker exec -it 5817dc8b00b9 bash chmod_csv.sh

