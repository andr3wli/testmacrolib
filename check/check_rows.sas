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

   @param expr= An expression indicating the tables for which row counts should be compared
   @param severity= Potential values: note, warning, error, abend (default to error)
 
   @author Mike Atkinson
   @author Andrew Li 
 **/

%macro check_rows(expr, severity=error, success_msg=%str(check_rows: All good));    
    %* Check the severity parameter;
    
    %if (not %sysfunc(prxmatch(/\b&severity\b/i, note warning warn error err abend abort))) %then %do;
        %let msg = If specified, severity should be one of: note, warning, error, abend.  The default is error;
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
        %let msg = Invalid expression;
        %goto not_ok;
    %end;
    
    %* If expression is OK thus far, can use pattern to pull out the LHS, comparison operator, and RHS;
    
    %let lhs = %sysfunc(prxchange(s/^([\s\w\+\-\*\.]+?)(=|<>|>=|<=|<|>){1}([\s\w\+\-\*\.]+)$/$1/, 1, &expr));
    %let cmp = %sysfunc(prxchange(s/^([\s\w\+\-\*\.]+?)(=|<>|>=|<=|<|>){1}([\s\w\+\-\*\.]+)$/$2/, 1, &expr));
    %let rhs = %sysfunc(prxchange(s/^([\s\w\+\-\*\.]+?)(=|<>|>=|<=|<|>){1}([\s\w\+\-\*\.]+)$/$3/, 1, &expr));
    
    %* Note: allowing libname to length 8 and dataset names up to length 32;
    %let lhs_ok = %sysfunc(prxmatch(%str(/^\s*((([a-z_]\w{0,7}\.){0,1}([a-z_]\w{0,31})|\d+)\s*(\+|\-|\*){1}\s*){0,}(([a-z_]\w{0,7}\.){0,1}[a-z_]\w{0,31}|\d+)\s*$/i), &lhs));
    %let rhs_ok = %sysfunc(prxmatch(%str(/^\s*((([a-z_]\w{0,7}\.){0,1}([a-z_]\w{0,31})|\d+)\s*(\+|\-|\*){1}\s*){0,}(([a-z_]\w{0,7}\.){0,1}[a-z_]\w{0,31}|\d+)\s*$/i), &rhs));
    
    %if (not (&lhs_ok and &rhs_ok)) %then %do;
        %if (not(&lhs_ok) and not(&rhs_ok)) %then
            %let msg = Invalid expression;
        %else %if (not(&lhs_ok)) %then
            %let msg = Invalid expression.  Might be problem before comparison operator;
        %else
            %let msg = Invalid expression.  Might be problem after comparison operator;
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
            %let msg = Table does not exist: &&tbl&i;
            %goto not_ok;
        %end;
    %end;
    
    
    %* Count the number of rows in each table using PROC SQL;
    
    proc sql  noprint;
    %do i = 1 %to &n_tables;
        %local row_count&i;
        select count(*) into :row_count&i from &&tbl&i;
    %end;
    quit;
    
    
    %* Substitute the number of rows for table names;
    
    %let expr_final = &expr;
    %do i = 1 %to &n_tables;
        %let expr_final = %sysfunc(prxchange(s/\b&&tbl&i\b/&&row_count&i/, 1, &expr_final));
    %end;
    
    
    %* Evaluate the expression;
    
    %if (%eval(%unquote(&expr_final)) ne 1) %then %do;
        %let msg = The following was false: &expr;
        %goto not_ok;
    %end;
    
    %* Success!  The expression was TRUE;
    %put &success_msg;
    
    
    %return; %* stop here if checks out (expression is true)!;
    
    %* if there was a problem or expression is false;
    %not_ok:
    %if (&severity = note)          %then %put NOTE: &msg;
    %else %if (&severity = warning) %then %do;
        %let syscc = %sysfunc(max(&syscc, 4));
        %put WARNING: &msg;
    %end;
    %else %if (&severity = error)   %then %do;
        %let syscc = %sysfunc(max(&syscc, 8));
        %put ERROR: &msg;
    %end;
    %else %if (&severity = abend)   %then %do;
        %let syscc = %sysfunc(max(&syscc, 8));
        %put Error: &msg;
        data _null_;
            abort abend;
        run;
    %end;
    %else %do;
        %let syscc = %sysfunc(max(&syscc, 8));
        %put ERROR: Oops, internal error. Unexpected severity: &severity;
    %end;
    %return;
    
    %mend;
    
    
