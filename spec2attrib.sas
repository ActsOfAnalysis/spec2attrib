/*soh***************************************************************************
 * CODE NAME           : spec2attrib.sas
 * DESCRIPTION         : Import domain metadata from an Excel specification
 *                       file, generate an ATTRIB block, and apply spec-defined
 *                       attributes directly to an input dataset to create a
 *                       standardized output dataset.
 * SPECIFICATIONS      : null
 * VALIDATION DETAILS  : null
 * MACRO USE           :
 * SOFTWARE/VERSION#   : SAS 9.4
 * DATA INPUT          :
 * OUTPUT              : 
 * MACRO PARAMETERS    :
 *   SPEC              = Specification file location
 *                       e.g., /path/spec/Analysis Dataset Specifications.xlsx
 *   DOMAIN            = Domain/dataset name
 *                       e.g., ADAE, ADTTE
 *   WHERE             = Optional filter on imported variable metadata
 *                       e.g., 1=1 (default)
 *   IN                = Input dataset
 *                       e.g., adam_src.adae
 *   OUT               = Output dataset
 *                       e.g., adam.adae
 *   DEBUG             = Debug flag controlling MPRINT/MLOGIC/SYMBOLGEN and
 *                       intermediate dataset cleanup
 *                       e.g., N (default), Y
 * SPECIAL INSTRUCTIONS:
 *   - SPEC, DOMAIN, IN, and OUT are required.
 *   - Variable metadata sheet name must match DOMAIN.
 *   - Dataset metadata sheet name must be "Domain List".
 * VERSION             :
 * AUTHOR              : GW
 * CREATION DATE       : 2026-06-19
 *
 * DOCUMENTATION AND REVISION HISTORY SECTION (required):
 * 
 * Date     Version Programmer Description
 * -------- ------- ---------- ----------------------------------
 * 20260619 V01     George Wu  Initial version
 *
 **eoh*************************************************************************/

%macro spec2attrib(SPEC=, DOMAIN=, WHERE=1=1, IN=, OUT=, DEBUG=N);

%global var_all var_sort ds_label;
%local opt_save;

** Save the calling session settings of all system options changed by this macro;
** They are restored at the end of the macro, including after an early exit on error;
%let opt_save=%sysfunc(getoption(validvarname,keyword))
  %sysfunc(getoption(validmemname,keyword))
  %sysfunc(getoption(varlenchk,keyword))
  %sysfunc(getoption(fmterr))
  %sysfunc(getoption(mprint))
  %sysfunc(getoption(mlogic))
  %sysfunc(getoption(symbolgen));
  
%let var_all=;
%let var_sort=;
%let ds_label=;
%let DOMAIN = %upcase(%superq(DOMAIN));
%let DEBUG=%upcase(%superq(DEBUG));

options validvarname=upcase validmemname=compatible 
  %if &DEBUG=Y %then mprint mlogic symbolgen;
  %else %if &DEBUG=N %then nomprint nomlogic nosymbolgen;
  ;

%if not %length(%superq(SPEC)) %then %do;
  %put ERROR: (&SYSMACRONAME) Macro parameter SPEC is required.;
  %goto exit;
%end;

%if not %length(%superq(DOMAIN)) %then %do;
  %put ERROR: (&SYSMACRONAME) Macro parameter DOMAIN is required.;
  %goto exit;
%end;

%if not %length(%superq(IN)) %then %do;
  %put ERROR: (&SYSMACRONAME) Macro parameter IN is required.;
  %goto exit;
%end;

%if not %length(%superq(OUT)) %then %do;
  %put ERROR: (&SYSMACRONAME) Macro parameter OUT is required.;
  %goto exit;
%end;

%if not %sysfunc(fileexist(%superq(SPEC))) %then %do;
  %put ERROR: (&SYSMACRONAME) Spec file does not exist: %superq(SPEC);
  %goto exit;
%end;

%if not %sysfunc(exist(%superq(IN))) %then %do;
  %put ERROR: (&SYSMACRONAME) Input dataset does not exist: %superq(IN);
  %goto exit;
%end;
 
** Import spec sheets;
*** 1. Variable Metadata;
proc import file="&SPEC" dbms=xlsx out=__meta__variable(where=(VARIABLE_NAME>''
  and (&WHERE))) replace;
  sheet="&DOMAIN";
  getnames=YES;
run;
 
*** 2. Dataset Metadata;
proc import file="&SPEC" dbms=xlsx out=__meta__dataset(where=(upcase(Domain)="&DOMAIN")) replace;
  sheet="Domain List";
  getnames=Yes;
run;

** Check if spec column Length is char or numeric after import and convert it to char if numeric;
data _null_;
  set sashelp.vcolumn(where=(upcase(libname)='WORK' and upcase(memname)='__META__VARIABLE' and upcase(name)='LENGTH'));
  if upcase(type)='NUM' then call execute ('
  data __meta__variable;
    set __meta__variable(rename=(length=length_));
    length Length $200;
    Length=strip(put(length_, best.));
  run;
  ');
run;
 
data __meta__01;
  set __meta__variable(keep=VARIABLE_NAME VARIABLE_LABEL KEY_SEQUENCE TYPE LENGTH FORMAT);
  ** make sure the duplicate check is not case-sensitive;
  VARIABLE_NAME = upcase(strip(VARIABLE_NAME));
  ORDER=_n_;
run;

proc sort data=__meta__01;
  by VARIABLE_NAME ORDER;
run;
 
proc sql noprint;
  select count(*) into: nspecrow trimmed from __meta__01;
quit;
 
** if spec does not exist then stop and put an error message;
%if &nspecrow ne 0 %then %do;
  ** Check if there are duplicate rows for the same variable;
  ** if yes, then keep metadata of the first entry;
  data __meta__02;
    set __meta__01;
    by VARIABLE_NAME ORDER;
    if first.VARIABLE_NAME then output;
    else put "WARN" "ING: (&SYSMACRONAME) Variable has duplicate entries in specification: " VARIABLE_NAME;
  run;
  
  proc sort data=__meta__02; by ORDER; run;

  ** ATTRIB block in external TEMP file;
        filename attrcode temp lrecl=32767;
  
        data _null_;
          set __meta__02 end=_eof_;
          file attrcode;

          length _len $32 _lbl $2000 _fmt $200 _line $4000 var_all $32767;
                retain var_all "  ";
                _skip=0;
                _line="";

          if _n_ = 1 then put 'attrib';

          if upcase(type) = 'CHAR' then do;
            if missing(length) then do;
                                _len = '$200';
                                putlog "WARN" "ING: (&SYSMACRONAME) CHAR length missing. Set to 200: " VARIABLE_NAME;
                        end;
            else _len = cats('$', strip(length));
          end;
                ** Numeric variables are always assigned LENGTH=8 regardless of spec LENGTH;
          else if upcase(type) = 'NUM' then _len = '8';
    else do;
                  putlog "WARN" "ING: (&SYSMACRONAME) Unrecognized TYPE for " variable_name ": " type
                      ". Variable skipped from generated ATTRIB block.";
                  _skip = 1;
                end;

          if not missing(variable_label) then
            _lbl = cats("label='", tranwrd(strip(variable_label), "'", "''"), "'");
          else do;
                        _lbl = '';
                        putlog "WARN" "ING: (&SYSMACRONAME) Variable label missing: " VARIABLE_NAME;
                end;

          if upcase(type) = 'NUM' and not missing(format) then do;
            if index(strip(format), '.') then _fmt = cats('format=', strip(format));
            else _fmt = cats('format=', strip(format), '.');
          end;
          else _fmt = '';

                if not _skip then do;
                  _line = catx(' ', variable_name, cats('length=', _len), _lbl, _fmt);
                        var_all=catx(' ',var_all, VARIABLE_NAME);
                        put '  ' _line;
                end;
          
          if _eof_ then do;
                        put ';';
                  call symputx('var_all',strip(var_all));
                end;
        run;

        %if not %length(%superq(var_all)) %then %do;
          %put ERROR: (&SYSMACRONAME) No valid variables remained after processing specification metadata.;
          %goto exit;
        %end;

        ** Sorting keys;
  proc sort data=__meta__02(where=(^missing(KEY_SEQUENCE))) 
    out=__meta__sort(keep=VARIABLE_NAME KEY_SEQUENCE)
    sortseq=linguistic(numeric_collation=on);
    by KEY_SEQUENCE;
  run;
 
  data _null_;
    set __meta__sort end=_eof_;
    by KEY_SEQUENCE;
    length var_sort $32767;
    retain var_sort;
    var_sort=catx(' ', var_sort, VARIABLE_NAME);
    if _eof_ then call symputx('var_sort', var_sort);
  run;
 
  ** Dataset label;
  proc sql noprint;
    select count(*) into: ndsspecrow trimmed from __meta__dataset;
  quit;
 
  ** if dataset metadata does not ;
  %if &ndsspecrow ne 0 %then %do;
    data _null_;
      set __meta__dataset(obs=1);
      call symputx('ds_label', DESCRIPTION);
    run;
  %end;
  %else %do;
    %put WARNING: Unable to find &DOMAIN. in spec dataset metadata tab;
    %let ds_label= ;
  %end;

  ** Read IN dataset and remove existing formats;
  ** keep &var_all let SAS fire a warning if variable in spec does not exist in IN dataset;
  data __meta__in;
    set &IN;
    keep &var_all;
    format _all_;
    informat _all_;
  run;

  ** SAS to fire a warning when a character variable is shortened;
  options varlenchk=warn;
  ** SAS to fire an error if SAS cannot find a format;
  options fmterr;

  data &OUT(label="&ds_label");
          ** Attrib block;
          %include attrcode / source2;
    set __meta__in;
          keep &var_all;
        run;

        %if %length(%superq(var_sort)) %then %do;
          proc sort data=&out;
            by &var_sort;
          run;
        %end;
%end;
%else %put ERROR: (&SYSMACRONAME) No specification is found for domain &DOMAIN..;

%if &DEBUG=N %then %do;
  proc datasets lib=work nolist;
    delete __meta__:;
  run; quit;
%end;
%if &DEBUG=Y and %sysfunc(exist(&OUT)) %then %do;
        %if %length(%superq(var_sort)) %then %do;
          proc sort data=&IN out=_in_data_;
            by &var_sort;
          run;
        %end;
  %else %do;
                data _in_data_; set &IN; run;
        %end;
  title "&SYSMACRONAME.: Comparing input-derived dataset _in_data_ and output &OUT.";
  proc compare b=_in_data_ c=&OUT listall ; run;
  title;
%end;

%exit:
** Restore the calling session option settings;
options &opt_save;

%mend spec2attrib;


