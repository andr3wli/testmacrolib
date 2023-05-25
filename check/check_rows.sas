 /**
   @file
   @brief Perform a check on table(s) row counts using the expression provided
   @details Looks at row counts for tables in the provided expression and checks 
    whether the expression is true or not. If not, prints a message (note, warning,
    error) and/or abends.
   Usage:
 
       %check_rows(%str( one=two ));
       %check_rows(%str( bad_has_time = 0 ));
       %check_rows(%str( bad_has_time = 0 ), severity=abend);
       %check_rows(%str( good_records > 0 ));
       %check_rows(%str( mylib.all = details + mylib2.summary ));

   @param expr= Unnamed Parm. An expression indicating the tables for which row counts should be compared
   @param severity= Named Parm. Potential values: note, warning, error, abend (default to error)
   @param commas= Named Parm. Default set to yes, with potential values of yes, no. Print dataset row counts with commas  for thousands, etc
   @param success_msg= Named Parm. Message to display in log if the row count expression checks out. Default: Success!
   
   @author Mike Atkinson
   @author Andrew Li 
 **/

 %if (not %sysfunc(prxmatch(/\b&severity\b/i, note warning warn error err abend abort))) %then %do;
 %let error_msg = If specified, severity should be one of: note, warning, error, abend.  The default is error;
 %let error_prefix = Expression;
 %let severity = error;
 %goto not_ok;
%end;
%else %do;
 %* standardise the severity values;
 %let severity = %lowcase(&severity);
 %if (&severity = warn)  %then %let severity = warning;
 %if (&severity = err)   %then %let severity = error;
 %if (&severity = abort) %then %let severity = abend;
%end;


%* Check that there is a comparison operator and only word characters and/or integers;

%let expr_ok_1 = %sysfunc(prxmatch(/^([\s\w\+\-\*\.]+?)(=|<>|>=|<=|<|>){1}([\s\w\+\-\*\.]+)$/, &expr));
%if (not &expr_ok_1) %then %do;
 %let error_msg = Invalid expression;
 %let error_prefix = Expression;
 %goto not_ok;
%end;

%* If expression is OK thus far, can use pattern to pull out the LHS, comparison operator, and RHS;

%let lhs = %sysfunc(prxchange(s/^([\s\w\+\-\*\.]+?)(=|<>|>=|<=|<|>){1}([\s\w\+\-\*\.]+)$/$1/, 1, &expr));
%let cmp = %sysfunc(prxchange(s/^([\s\w\+\-\*\.]+?)(=|<>|>=|<=|<|>){1}([\s\w\+\-\*\.]+)$/$2/, 1, &expr));
%let rhs = %sysfunc(prxchange(s/^([\s\w\+\-\*\.]+?)(=|<>|>=|<=|<|>){1}([\s\w\+\-\*\.]+)$/$3/, 1, &expr));

%if (&cmp = %str(<>)) %then
 %let cmp = ne;

%* default if not set later;
%let eval_lhs = &lhs;
%let eval_rhs = &rhs;


%* Note: allowing libname to length 8 and dataset names up to length 32;
%let lhs_ok = %sysfunc(prxmatch(%str(/^\s*((([a-z_]\w{0,7}\.){0,1}([a-z_]\w{0,31})|\d+)\s*(\+|\-|\*){1}\s*){0,}(([a-z_]\w{0,7}\.){0,1}[a-z_]\w{0,31}|\d+)\s*$/i), &lhs));
%let rhs_ok = %sysfunc(prxmatch(%str(/^\s*((([a-z_]\w{0,7}\.){0,1}([a-z_]\w{0,31})|\d+)\s*(\+|\-|\*){1}\s*){0,}(([a-z_]\w{0,7}\.){0,1}[a-z_]\w{0,31}|\d+)\s*$/i), &rhs));

%if (not (&lhs_ok and &rhs_ok)) %then %do;
 %if (not(&lhs_ok) and not(&rhs_ok)) %then
     %let error_msg = Invalid expression;
 %else %if (not(&lhs_ok)) %then
     %let error_msg = Invalid expression.  Might be problem before comparison operator;
 %else
     %let error_msg = Invalid expression.  Might be problem after comparison operator;
 %let error_prefix = Expression;
 %goto not_ok;
%end;


%* Loop through both left-hand-side and right-hand-side to find all the table names;

%let n_tables = 0;
%let i = 1;

%let a_tbl = %scan(&lhs &rhs, &i, %str( +-*));
%do %while (&a_tbl ne %str());
 %* ensure numbers are excluded;
 %if (%sysfunc(prxmatch(%str(/^[a-z]/i), &a_tbl))) %then %do;
     %let n_tables = %eval(&n_tables + 1);
     %let tbl&n_tables = &a_tbl;
 %end;

 %let i = %eval(&i + 1);
 %let a_tbl = %scan(&lhs &rhs, &i, %str( +-*));
%end;


%* Ensure each table exists;

%do i = 1 %to &n_tables;
 %if (not %sysfunc(exist(&&tbl&i))) %then %do;
     %let error_msg = Table does not exist: &&tbl&i;
     %let error_prefix = Expression;
     %goto not_ok;
 %end;
%end;


%* Count the number of rows in each table using PROC SQL;

proc sql  noprint;
%do i = 1 %to &n_tables;
 %local row_count&i;
 select left(put(count(*), best15.)) into :row_count&i from &&tbl&i;
%end;
quit;


%* Substitute the number of rows for table names;

%let expr_final = &lhs &cmp &rhs;
%do i = 1 %to &n_tables;
 %let row_count = %trim(&&row_count&i);
 %let expr_final = %sysfunc(prxchange(s/\b&&tbl&i\b/&row_count/, 1, &expr_final));
 %let lhs        = %sysfunc(prxchange(s/\b&&tbl&i\b/&row_count/, 1, &lhs));
 %let rhs        = %sysfunc(prxchange(s/\b&&tbl&i\b/&row_count/, 1, &rhs));
%end;


%* Add thousands commas (if that option is turned on);
%* (Note: credit to OReilly - Goyvaerts, Levithan - for the regular expression that inserts commas);
%if (%sysfunc(prxmatch(/^\s*y/i, &commas))) %then %do;
 %let expr_final_print = %sysfunc(prxchange(%str(s/\d(?=(?:\d{3})+(?!\d))/$0,/), -1, &expr_final));
 %let lhs_print        = %sysfunc(prxchange(%str(s/\d(?=(?:\d{3})+(?!\d))/$0,/), -1, &lhs));
 %let rhs_print        = %sysfunc(prxchange(%str(s/\d(?=(?:\d{3})+(?!\d))/$0,/), -1, &rhs));
%end;
%else %do;
 %let expr_final_print = &expr_final;
 %let lhs_print        = &lhs;
 %let rhs_print        = &rhs;
%end;


%* Evaluate the expression to see if check_rows was successful;

%* Do LHS and RHS separately for the log;
%let eval_lhs = %eval(&lhs);
%let eval_rhs = %eval(&rhs);

%* Add thousands commas if that option is turned on;
%if (%sysfunc(prxmatch(/^\s*y/i, &commas))) %then %do;
 %let eval_lhs_print = %sysfunc(prxchange(%str(s/\d(?=(?:\d{3})+(?!\d))/$0,/), -1, &eval_lhs));
 %let eval_rhs_print = %sysfunc(prxchange(%str(s/\d(?=(?:\d{3})+(?!\d))/$0,/), -1, &eval_rhs));
%end;
%else %do;
 %let eval_lhs_print = &eval_lhs;
 %let eval_rhs_print = &eval_rhs;
%end;

%* Check whether the entire expression is true or not;
%if (%eval(%unquote(&expr_final)) ne 1) %then %do;
 %let error_msg = Expression Failed!;
 %let error_prefix = Not True;
 %goto not_ok;
%end;

%* Success!  The expression was TRUE;
%put NOTE: check_rows: &success_msg;
%put NOTE: check_rows: %left(&expr);                 %* original expression;
%put NOTE: check_rows: &lhs_print &cmp &rhs_print;   %* with row counts in place of table names;
%* next note applies if there are multiple row counts on either side of expression;
%if ((%quote(&lhs) ne %quote(&eval_lhs)) or (%quote(&rhs) ne %quote(&eval_rhs))) %then
 %put NOTE: check_rows: &eval_lhs_print &cmp &eval_rhs_print;

%put; %* a blank line after messages;
%return; %* stop here if checks out (expression is true)!;


%* if there was a problem or expression is false;
%not_ok:
%if (&severity = note)          %then %let msg_type = NOTE;
%else %if (&severity = warning) %then %do;
 %let syscc = %sysfunc(max(&syscc, 4));
 %let msg_type = WARNING;
%end;
%else %if (&severity = error)   %then %do;
 %let syscc = %sysfunc(max(&syscc, 8));
 %let msg_type = ERROR;
%end;
%else %if (&severity = abend)   %then %do;
 %let syscc = %sysfunc(max(&syscc, 8));
 %let msg_type = ERROR;
%end;
%else %do;
 %let syscc = %sysfunc(max(&syscc, 8));
 %put ERROR: check_rows: Oops, internal error. Unexpected severity: &severity;
 %put; %* a blank line after messages;
 %return;
%end;

%put &msg_type: check_rows: &error_msg;
%put &msg_type: check_rows: &error_prefix: %left(&expr);
%if (%quote(&error_prefix) = %str(Not True)) %then %do;
 %put &msg_type: check_rows: &error_prefix: &lhs_print &cmp &rhs_print;
 %if ((%quote(&lhs) ne %quote(&eval_lhs)) or (%quote(&rhs) ne %quote(&eval_rhs))) %then
     %put &msg_type: check_rows: &error_prefix: &eval_lhs_print &cmp &eval_rhs_print;
%end;

%* If severity level is ABEND, abort execution;
%if (&severity = abend) %then %do;
 data _null_;
     abort abend;
 run;
%end;

%put; %* a blank line after messages;

%return;

%mend check_rows;

    
    
