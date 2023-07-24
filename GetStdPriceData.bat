@echo off

chcp 65001 > nul

rem --------------------------------------------------
rem 定数（DB接続パラメータなど）
rem --------------------------------------------------
set PGPATH="C:\Program Files\PostgreSQL\14\bin\"
set HOSTNAME=localhost
set PORTNUM=5432
set DBNAME=postgres
set USERNAME=postgres
set PGPASSWORD=e1427633
set FILENAME_URL=urls.txt
set CACHE_MAX_BULK_INS=200

set SQL_SEL="SELECT fm.fund_id,fm.fund_name,'https://'||fm.csv_url AS csv_url,COALESCE(fsp.std_date,'19000101'::DATE)AS std_date_latest,COALESCE(fsp.std_price,0)AS std_price_latest FROM fund_manage fm LEFT JOIN(SELECT fsp.fund_id,MAX(fsp.std_date)std_date FROM fund_std_price fsp GROUP BY fsp.fund_id)fsp_max ON fm.fund_id=fsp_max.fund_id LEFT JOIN fund_std_price fsp ON fsp.fund_id=fsp_max.fund_id AND fsp.std_date=fsp_max.std_date WHERE LENGTH(fm.csv_url)>0 ORDER BY fm.fund_id;"

%PGPATH%psql -h %HOSTNAME% -p %PORTNUM% -d %DBNAME% -U %USERNAME% -c %SQL_SEL% | findstr /r /c:[0-9][0-9][0-9][0-9][/-]*[0-9][0-9][/-]*[0-9][0-9] > %FILENAME_URL%

setlocal enabledelayedexpansion

set VALUES_LIST=
set COMMA=
set /a INS_COUNT_SUM=0
set /a INS_COUNT_SUM_TMP=0

for /f "delims=" %%r in (%FILENAME_URL%) do (

	set LINE=%%r
	set LINE=!LINE: ^| =,!
rem	echo [LINE]!LINE!

	set FUND_ID=
	set FUND_NAME=
	set URL_CSV=
	set STD_DATE_LATEST=
	set STD_DATE_LATEST_FMT=
	set /a STD_PRICE_LATEST=0

	for /f "tokens=1,2,3,4,5 delims=," %%a in ('echo "!LINE!"') do (
		set FUND_ID=%%a
		set FUND_ID=!FUND_ID:"=!
		set FUND_ID=!FUND_ID: =!
		set FUND_NAME=%%b
		set URL_CSV=%%c
		set URL_CSV=!URL_CSV: =!
		set STD_DATE_LATEST=%%d
		set STD_DATE_LATEST=!STD_DATE_LATEST: =!
		set STD_DATE_LATEST=!STD_DATE_LATEST:-=/!
		set STD_DATE_LATEST_FMT=!STD_DATE_LATEST!
		set STD_DATE_LATEST=!STD_DATE_LATEST:/=!
		set STD_PRICE_LATEST=%%e
		set STD_PRICE_LATEST=!STD_PRICE_LATEST:"=!
		set STD_PRICE_LATEST=!STD_PRICE_LATEST: =!
	)

	set STD_DATE_LATEST_NEW_FMT=!STD_DATE_LATEST_FMT!
	set STD_PRICE_LATEST_NEW=!STD_PRICE_LATEST!
	set /a FIRST_FLG=1

	for /f "tokens=1,2 delims=," %%f in ('curl -sS "!URL_CSV!" ^| findstr /r /c:[0-9][0-9][0-9][0-9][/-]*[0-9][0-9][/-]*[0-9][0-9] ^| sort /r') do (
		set STD_DATE=%%f
		set STD_DATE=!STD_DATE:"=!
		set STD_DATE=!STD_DATE:-=!
		set STD_DATE=!STD_DATE:/=!
		if !STD_DATE! gtr !STD_DATE_LATEST! (
			set STD_PRICE=%%g
			set STD_PRICE=!STD_PRICE:"=!
			set STD_PRICE=!STD_PRICE:.00=!
rem			echo [FUND_ID],[STD_DATE],[STD_PRICE]:!FUND_ID!,!STD_DATE!,!STD_PRICE!
			if !FIRST_FLG! equ 1 (
				set STD_DATE_LATEST_NEW_FMT=!STD_DATE:~0,4!/!STD_DATE:~4,2!/!STD_DATE:~6,2!
				set STD_PRICE_LATEST_NEW=!STD_PRICE!
				set /a FIRST_FLG=0
			)
			set VALUES="('!FUND_ID!'^,'!STD_DATE!'::DATE^,!STD_PRICE!)"
			set VALUES_LIST=!VALUES_LIST!!COMMA!!VALUES:"=!
			set COMMA=^,
			set /a INS_COUNT_SUM=!INS_COUNT_SUM!+1
			set /a INS_COUNT_SUM_TMP=!INS_COUNT_SUM_TMP!+1
			if !INS_COUNT_SUM_TMP! geq !CACHE_MAX_BULK_INS! (
				call :func_insert
			)
		)
	)

	echo [!FUND_ID!]!FUND_NAME!
	echo   [Standard Price]
	if !STD_PRICE_LATEST! gtr 0 (
		echo     [Old] !STD_DATE_LATEST_FMT! ^: !STD_PRICE_LATEST!
		if not !STD_DATE_LATEST_NEW_FMT! == !STD_DATE_LATEST_FMT! (
			set /a DIFF=!STD_PRICE_LATEST_NEW!-!STD_PRICE_LATEST!
			set SIGN=
			if !DIFF! gtr 0 (
				set SIGN=+
			)
			echo     [New] !STD_DATE_LATEST_NEW_FMT! ^: !STD_PRICE_LATEST_NEW! ^(!SIGN!!DIFF!^)
		) else (
			echo     [New] !STD_DATE_LATEST_NEW_FMT! ^: !STD_PRICE_LATEST_NEW!
		)
	) else (
		echo     [New] !STD_DATE_LATEST_NEW_FMT! ^: !STD_PRICE_LATEST_NEW!
	)
	echo;

)

del %FILENAME_URL%

if !INS_COUNT_SUM_TMP! gtr 0 (
	call :func_insert
)

echo  !INS_COUNT_SUM! records is added.
echo;

endlocal

pause

exit /b

:func_insert
	set SQL_INS="INSERT INTO fund_std_price VALUES !VALUES_LIST!;"
rem	echo [SQL_INS]%SQL_INS%
	%PGPATH%psql -h %HOSTNAME% -p %PORTNUM% -d %DBNAME% -U %USERNAME% -c %SQL_INS% > nul
	set VALUES_LIST=
	set COMMA=
	set /a INS_COUNT_SUM_TMP=0
exit /b

