
1. Create a test script under /net/slc14ymz/scratch/aaramakr/run_db_from_perl/rahul in slc14ymz.us.oracle.com

   a. Copy the existing scripts there and modify accordingly
   b. Do not have any instructions to update the database or removal of files


2. Go to APF grid report and find out the hosts associated to below grids
   
   OEL7: APF_OEL7_PBUILD_GRID
   OEL6: APF_DB122_PBUILD_GRID
   OEL5: APF_64BIT_OEL5_PBUILD_GRID	
   OEL4: APF_PBUILD_GRID, APF_PROACTIVE_GRID_64

   Copy Grid ID and search in the page

3. ssh into the specific machine

4. sudo as apfmgr
   sudo su - apfmgr

5. Source the env file
   source ~/o.env

6. Compile check the script

   perl -c <script location/file.pl>

   perl -c /net/slc14ymz//scratch/aaramakr/run_db_from_perl/rahul/ARU_extraction_test.pl

6. Execute the script

   perl <script location/file.pl>

   perl /net/slc14ymz//scratch/aaramakr/run_db_from_perl/rahul/ARU_extraction_test.pl


Execute:

	% perl -c /net/slc14ymz//scratch/aaramakr/run_db_from_perl/rahul/ARU_extraction_test.pl 
	/net/slc14ymz//scratch/aaramakr/run_db_from_perl/rahul/ARU_extraction_test.pl syntax OK


	{slc11wyl:apfmgr:::10.2.0.4.0} /home/apfmgr% perl /net/slc14ymz//scratch/aaramakr/run_db_from_perl/rahul/ARU_extraction_test.pl

	Printing bug update message : Bug 32647468 TRACKING BUG: BUG 31544340 - ADR FOR WEBLOGIC SERVER 12.2.1.3.0 JULY CPU 2020 FOR WEBLOGIC SERVER SPB 
	Bug 33902200 Coherence 12.2.1.3 Cumulative Patch 18 (12.2.1.3.18) 
	Bug 32982708 FMW PLATFORM 12.2.1.3.0 SPU FOR APRCPU2021 
	Bug 32148634 WEBLOGIC SAMPLES SPU 12.2.1.3.210119 
	Bug 33290784 JDBC 12.2.0.1 FOR CPUJAN2022 (WLS 12.2.1.3) 
	Bug 34010914 WLS PATCH SET UPDATE 12.2.1.3.220329 
	Bug 33959179 OBI BUNDLE PATCH 12.2.1.3.220314 
	Bug 28186730 OPATCH 13.9.4.2.8 FOR EM 13.4, 13.5 AND FMW/WLS 12.2.1.3.0, 12.2.1.4.0 AND 14.1.1.0.0 
	Bug 33918887 TRACKING BUG FOR SPBAT VERSION 2.0.0 FOR WLS-SOA-OBI {slc11wyl:apfmgr:::10.2.0.4.0} /home/apfmgr% 