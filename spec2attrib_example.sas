/*******************************************************************************
* Program : spec2attrib_example.sas
* Purpose : Worked example for the preprint "A Metadata-Driven ATTRIB Macro for
*           Standardizing SAS Datasets from Excel Specifications".
*
*           1. Builds a small ADSL specification workbook (sheets ADSL and
*              Domain List) with PROC EXPORT
*           2. Builds an input dataset whose attributes deliberately differ
*              from the specification
*           3. Runs %spec2attrib
*           4. Reports the generated ATTRIB block and the attributes of the
*              input and output datasets
*
* Usage   : Set OUTDIR and MACDIR below, then submit the whole program.
*           Everything is written to OUTDIR:
*             spec2attrib_example.log  - SAS log
*             spec2attrib_example.lst  - results (plain text)
*             example_spec.xlsx        - the specification workbook
*           The log goes to the file, not the Log window, while it runs.
*******************************************************************************/

%let outdir = C:\temp\spec2attrib_example;  /* output folder, created if needed    */
%let macdir = C:\path\to\spec2attrib;       /* folder containing spec2attrib.sas   */

/* Create the output folder if it does not exist */
options dlcreatedir;
libname _exdir "&outdir";
libname _exdir clear;

/* Route the log and results to files in OUTDIR */
proc printto log="&outdir/spec2attrib_example.log" new; run;
ods listing file="&outdir/spec2attrib_example.lst";
options nodate nonumber linesize=200 pagesize=max formchar="|----|+|---+=|-/\<>*";

%put NOTE: SAS &sysvlong on &sysscpl;

title "spec2attrib worked example";
data _null_;
  file print;
  put "SAS version: &sysvlong    Platform: &sysscpl    Run date: &sysdate9";
run;

/*------------------------------------------------------------------------------
* 1. Specification workbook
*-----------------------------------------------------------------------------*/
data spec_adsl;
  length VARIABLE_NAME $8 VARIABLE_LABEL $40 TYPE $4 FORMAT $8;
  infile datalines dsd dlm='|' truncover;
  input VARIABLE_NAME VARIABLE_LABEL TYPE LENGTH FORMAT KEY_SEQUENCE;
datalines;
STUDYID|Study Identifier|Char|12||1
USUBJID|Unique Subject Identifier|Char|20||2
SUBJID|Subject Identifier for the Study|Char|8||
AGE|Age|Num|8||
SEX|Sex|Char|1||
TRT01P|Planned Treatment for Period 01|Char|20||
TRTSDT|Date of First Exposure to Treatment|Num|8|DATE9|
;
run;

data spec_domains;
  length DOMAIN $8 DESCRIPTION $40;
  infile datalines dsd dlm='|' truncover;
  input DOMAIN DESCRIPTION;
datalines;
ADSL|Subject-Level Analysis Dataset
ADAE|Adverse Events Analysis Dataset
;
run;

proc export data=spec_adsl outfile="&outdir/example_spec.xlsx" dbms=xlsx replace;
  sheet="ADSL";
run;

proc export data=spec_domains outfile="&outdir/example_spec.xlsx" dbms=xlsx replace;
  sheet="Domain List";
run;

/* Confirm both sheets are in the workbook */
libname _spec xlsx "&outdir/example_spec.xlsx";
title "1a. Sheets in example_spec.xlsx";
proc sql;
  select memname from dictionary.tables where libname='_SPEC';
quit;
libname _spec clear;

title "1b. Specification sheet ADSL";
proc print data=spec_adsl noobs; run;

title "1c. Specification sheet Domain List";
proc print data=spec_domains noobs; run;

/*------------------------------------------------------------------------------
* 2. Input dataset. Its attributes deliberately differ from the specification:
*    - generic character lengths ($200, $40, $20, $8)
*    - inherited formats: $200. on USUBJID and BEST12. on AGE
*    - no labels, and no format on the date variable TRTSDT
*    - variable order differs from the specification
*    - WORKFLG is a work variable that is not in the specification
*    - records are not sorted
*-----------------------------------------------------------------------------*/
data adsl_src;
  length USUBJID STUDYID $200 AGE 8 SEX $8 SUBJID $20 TRT01P $40 TRTSDT 8 WORKFLG $1;
  format USUBJID $200. AGE best12.;
  infile datalines dsd dlm='|' truncover;
  input USUBJID STUDYID AGE SEX SUBJID TRT01P TRTSDT :date9. WORKFLG;
datalines;
XYZ-101-003|XYZ-101|54|F|003|Drug A 10 mg|12MAR2025|Y
XYZ-101-001|XYZ-101|61|M|001|Placebo|03MAR2025|N
XYZ-101-004|XYZ-101|47|M|004|Drug A 10 mg|14MAR2025|Y
XYZ-101-002|XYZ-101|58|F|002|Placebo|05MAR2025|N
;
run;

/*------------------------------------------------------------------------------
* 3. Run the macro. A few options are first set to non-default values so the
*    log shows whether the macro restores them afterwards.
*-----------------------------------------------------------------------------*/
options validvarname=v7 varlenchk=nowarn nofmterr mprint;
%put NOTE: Options before macro: %sysfunc(getoption(validvarname,keyword)) %sysfunc(getoption(varlenchk,keyword)) %sysfunc(getoption(fmterr)) %sysfunc(getoption(mprint));

%include "&macdir/spec2attrib.sas";

%spec2attrib(
  SPEC   = &outdir/example_spec.xlsx,
  DOMAIN = ADSL,
  IN     = work.adsl_src,
  OUT    = work.adsl,
  DEBUG  = N
);

%put NOTE: Options after macro:  %sysfunc(getoption(validvarname,keyword)) %sysfunc(getoption(varlenchk,keyword)) %sysfunc(getoption(fmterr)) %sysfunc(getoption(mprint));

/*------------------------------------------------------------------------------
* 4. Results
*-----------------------------------------------------------------------------*/

/* 4a. The ATTRIB block generated by the macro (temporary fileref ATTRCODE) */
title '4a. ATTRIB block generated by %spec2attrib';
data _null_;
  infile attrcode;
  file print;
  input;
  put _infile_;
run;

/* 4b. Variable attributes of the input and output datasets, side by side */
proc sql;
  create table attr_compare as
  select coalesce(o.name, i.name) as Variable length=32,
         i.varnum as In_Pos,
         i.type   as In_Type,
         i.length as In_Len,
         i.format as In_Format length=12,
         i.label  as In_Label  length=40,
         o.varnum as Out_Pos,
         o.type   as Out_Type,
         o.length as Out_Len,
         o.format as Out_Format length=12,
         o.label  as Out_Label length=40,
         coalesce(o.varnum, 999) as _ord
  from (select * from dictionary.columns
        where libname='WORK' and memname='ADSL_SRC') as i
       full join
       (select * from dictionary.columns
        where libname='WORK' and memname='ADSL') as o
  on upcase(i.name) = upcase(o.name)
  order by _ord;
quit;

title "4b. Variable attributes: input WORK.ADSL_SRC (In_) vs output WORK.ADSL (Out_)";
proc print data=attr_compare noobs;
  var Variable In_: Out_:;
run;

/* 4c. Dataset-level attributes of the output: label and sort order */
title "4c. Output dataset WORK.ADSL: dataset label and sort order";
ods select Attributes Sortedby;
proc contents data=adsl; run;

/* 4d-4e. Data before and after */
title "4d. Input dataset WORK.ADSL_SRC";
proc print data=adsl_src noobs; run;

title "4e. Output dataset WORK.ADSL";
proc print data=adsl noobs; run;

title;
ods listing close;
proc printto; run;
