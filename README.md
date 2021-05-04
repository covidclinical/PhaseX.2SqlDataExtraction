# PhaseX.2SqlDataExtraction
SQL and documentation to extract 4CE Phase 1.2 and 2.2 data files.

There is now a single SQL script that can generate both Phase 1.2 and 2.2 data files in CSV format. However, by default, it will only generate Phase 1.2 files. Change the configuration settings at the top of the script to include Phase 2.2. It is important that you generate both Phase 1.2 and 2.2 files at the same time so that the data in both sets of files match.

By default, the files will only include patients with a positive SARS-CoV-2 test result who were admitted between -7 and +14 days of the test. Additional configuration settings at the top of the script can be changed to add patients with a U07.1 diagnosis code, a negative test result, and those who were not admitted to the files. We encourage all sites to include these additional cohorts if your IRB and institution allows it.

Upload your Phase 1.2 files (obfuscated aggregate counts and statistics) to

https://connects.catalyst.harvard.edu/4ce

Your Phase 2.2 files (non-obfuscated aggregate files and patient-level data files) should never leave your institution.

A PowerPoint overview of Phase X.2 files can be found at

https://github.com/covidclinical/PhaseX.2SqlDataExtraction/blob/main/4CE_PhaseX.2_File_Overview.pptx

Detailed descriptions of all the files can be found at

https://github.com/covidclinical/PhaseX.2SqlDataExtraction/blob/main/4CE_PhaseX.2_File_Descriptions.xlsx

Make sure your healthcare system information is accurate in the 4CE site list at

https://docs.google.com/spreadsheets/d/1Xl9juDBXt86P3xQtsoTaBl2zPl1BIiAG9DI3Rotyqp8/edit#gid=212461777


RELEASE NOTES

2021-05-04: Set the default database schema to "dbo."; set replace_patient_num=0 by default; fixed bugs in optional SQL to get an expanded list of medication and procedure codes from the ACT ontology.

2021-04-21: Initial version of the MSSQL script.



