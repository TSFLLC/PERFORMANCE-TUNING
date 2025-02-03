

--optimize script

USE [DBA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[lsp_long_running_queries] 
AS 
SET NOCOUNT ON;

DECLARE @servername VARCHAR(256);
DECLARE @xml NVARCHAR(MAX);
DECLARE @body NVARCHAR(MAX);
DECLARE @longrunningthreshold INT;
DECLARE @subject VARCHAR(256);
DECLARE @mydate DATETIME;
DECLARE @recipients VARCHAR(MAX);

SET @mydate = GETDATE();
SET @servername = UPPER(@@SERVERNAME);
SET @subject = 'ALERT: Long Running Queries on ' + @servername + ' - ' + CONVERT(VARCHAR(10), @mydate, 101) + RIGHT(CONVERT(VARCHAR(32), @mydate, 100), 8);
SET @recipients = 'SERGE.TCHUENTEU@GMAIL.COM';

-- Set threshold (in minutes) for long-running queries
SET @longrunningthreshold = 10;

-- Step 1: Collect Long Running Queries
WITH RunningQueries AS (
    SELECT 
        r.session_id AS [SPID],
        s.login_name AS [LogIName],
        s.host_name AS [HostName],
        DB_NAME(r.database_id) AS [DB],
        r.start_time AS [Start_Time],
        DATEDIFF(MINUTE, r.start_time, GETDATE()) AS [Duration],
        s.status AS [Status],
        SUBSTRING(t.text, (r.statement_start_offset/2) + 1, 
            ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text) ELSE r.statement_end_offset END - r.statement_start_offset)/2) + 1) AS [Query_Text]
    FROM sys.dm_exec_requests r
    INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.database_id > 4 
        AND r.start_time IS NOT NULL 
        AND DATEDIFF(MINUTE, r.start_time, GETDATE()) >= @longrunningthreshold
        AND s.is_user_process = 1 -- Exclude system processes
)
SELECT @xml = CAST((
    SELECT 
        [SPID] AS 'td', '', 
        [Start_Time] AS 'td', '', 
        [Duration] AS 'td', '', 
        [Status] AS 'td', '', 
        [LogIName] AS 'td', '', 
        [HostName] AS 'td', '', 
        [DB] AS 'td', '', 
        [Query_Text] AS 'td', ''
    FROM RunningQueries
    FOR XML PATH('tr'), ELEMENTS
) AS NVARCHAR(MAX));

-- Step 2: Generate HTML Body
SET @body = 
'<html>
    <body>
        <h2>Long Running Queries (Threshold > ' + CAST(@longrunningthreshold AS VARCHAR) + ' Minutes) </h2>
        <table border="1" style="border-color: black; border-collapse: collapse;">
            <tr>
                <th>SPID</th>
                <th>Start_Time</th>
                <th>Duration (Min)</th>
                <th>Status</th>
                <th>Login Name</th>
                <th>Host Name</th>
                <th>Database</th>
                <th>Query</th>
            </tr>' + @xml + 
        '</table>
    </body>
</html>';

-- Step 3: Send Email if Queries Exceed Threshold
IF (@xml IS NOT NULL)
BEGIN
    EXEC msdb.dbo.sp_send_dbmail 
        @profile_name = 'SQLAdmin', 
        @recipients = @recipients, 
        @subject = @subject, 
        @body = @body, 
        @body_format = 'HTML';
END;

RETURN(0);
GO


--------------------------------------------------------Revised script----------------------------------------------

USE [DBA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[lsp_long_running_queries] 
AS
SET NOCOUNT ON;

DECLARE @servername VARCHAR(256);
DECLARE @xml NVARCHAR(MAX);
DECLARE @body NVARCHAR(MAX);
DECLARE @longrunningthreshold INT;
DECLARE @subject VARCHAR(256);
DECLARE @mydate DATETIME;
DECLARE @recipients VARCHAR(MAX);

SET @mydate = GETDATE();
SET @servername = UPPER(@@servername);
SET @subject = 'ALERT: Long Running Queries on ' + @servername + 
               ' - ' + CONVERT(VARCHAR(10), @mydate, 101) + 
               ' ' + RIGHT(CONVERT(VARCHAR(32), @mydate, 100), 8);
SET @recipients = 'SERGE.TCHUENTEU@GMAIL.COM';  -- Update recipient email if needed
SET @longrunningthreshold = 10; -- In minutes

-- Step 1: Collect Long Running Query Details
WITH cte AS (
    SELECT 
        r.session_id AS [SPID],
        r.start_time AS [Start_Time],
        LTRIM(RTRIM(s.status)) AS [Status],
        DATEDIFF(MINUTE, r.start_time, GETDATE()) AS [Duration],
        s.login_name AS [LogIName],
        s.host_name AS [HostName],
        DB_NAME(r.database_id) AS [DB],
        SUBSTRING(t.text, (r.statement_start_offset/2) + 1, 
                  ((CASE r.statement_end_offset 
                        WHEN -1 THEN DATALENGTH(t.text) 
                        ELSE r.statement_end_offset 
                    END - r.statement_start_offset) / 2) + 1) AS [Query]
    FROM sys.dm_exec_requests r
    INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.database_id > 4 
        AND s.status NOT LIKE '%sleeping%'
        AND r.command NOT LIKE '%BACKUP%'
        AND r.command NOT LIKE '%UPDATE STATISTICS%'
)

-- Step 2: Generate HTML Table
SELECT @xml = CAST( 
    ( SELECT 
        [SPID] AS 'td', '', 
        [Start_Time] AS 'td', '', 
        [Duration] AS 'td', '', 
        [Status] AS 'td', '', 
        [LogIName] AS 'td', '', 
        [HostName] AS 'td', '', 
        [DB] AS 'td', '', 
        [Query] AS 'td', ''
      FROM cte 
      WHERE [Duration] >= @longrunningthreshold 
      FOR XML PATH('tr'), ELEMENTS 
    ) AS NVARCHAR(MAX));

-- Step 3: Format HTML Body
SET @body = 
    '<html> 
        <body> 
            <H2>Long Running Queries (Threshold > ' + CAST(@longrunningthreshold AS VARCHAR) + ' Minute(s))</H2> 
            <table border="1" BORDERCOLOR="Black"> 
                <tr> 
                    <th>SPID</th> 
                    <th>Start Time</th> 
                    <th>Duration (Min)</th> 
                    <th>Status</th> 
                    <th>Login Name</th> 
                    <th>Host Name</th> 
                    <th>Database</th> 
                    <th>Query</th> 
                </tr>' + @xml + 
            '</table>
        </body>
    </html>';

-- Step 4: Send Email if Long Running Queries Exist
IF (@xml IS NOT NULL)
BEGIN
    EXEC msdb.dbo.sp_send_dbmail 
        @profile_name = 'SQLAdmin', 
        @body = @body, 
        @body_format = 'HTML', 
        @recipients = @recipients, 
        @subject = @subject;
END;

RETURN(0);
GO



----------------------------------------------------Original script------------------------------------

USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[lsp_long_running_queries]    Script Date: 12/1/2024 8:38:42 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE PROCEDURE [dbo].[lsp_long_running_queries]
AS
     SET NOCOUNT ON;

     DECLARE @servername VARCHAR(256);
     DECLARE @xml NVARCHAR(MAX);
     DECLARE @body NVARCHAR(MAX);
     DECLARE @longrunningthreshold INT;
     DECLARE @subject VARCHAR(256);
     DECLARE @mydate DATETIME;
     DECLARE @recipients VARCHAR(MAX);

     SET @mydate = GETDATE();
     SET @servername =
(
    SELECT UPPER(@@servername)
);
     SET @subject = 'ALERT: Long Running Queries on '+@servername+'. '+CONVERT(VARCHAR(10), @mydate, 101)+RIGHT(CONVERT(VARCHAR(32), @mydate, 100), 8);
     SET @recipients = 'serge.tchuenteu@gmail.com';

-- SPECIFY LONG RUNNING QUERY DURATION THRESHOLD
     SET @longrunningthreshold = 10;

-- STEP 1: COLLECT LONG RUNNING QUERY DETAILS.
     WITH cte
          AS (
          SELECT    [SPID] = [spid],
                    [Start_Time] =
(
    SELECT [start_time]
    FROM    [sys].[dm_exec_requests]
    WHERE  [spid] = [session_id]
),
                    [Status] = LTRIM(RTRIM([status])),
                    [Duration] = DATEDIFF([mi],
(
    SELECT [start_time]
    FROM   [sys].[dm_exec_requests]
    WHERE  [spid] = [session_id]
), GETDATE()),
                    [LogIName],
                    [HostName],
                    [DB] =
(
    SELECT [sdb].[name]
    FROM   [MASTER]..[sysdatabases] [sdb]
    WHERE  [sdb].[dbid] = [qs].[dbid]
),
                    [Query] = SUBSTRING([st].[text], ([qs].[stmt_start]/2)+1, ((CASE [qs].[stmt_end]
                                                                                    WHEN-1
                                                                                    THEN DATALENGTH([st].text)
                                                                                    ELSE [qs].[stmt_end]
                                                                                END-[qs].[stmt_start])/2)+1),
                    text
          FROM [sys].[sysprocesses] [qs]
               CROSS APPLY [sys].[Dm_exec_sql_text]([sql_handle]) [st]
          WHERE [qs].[dbid] > 4
                AND ([CMD] NOT LIKE '%BACKUP%'
                AND [CMD] NOT LIKE '%UPDATE STATISTICS%')
                AND [LogIName] NOT LIKE '%mazeika%')

-- STEP 2: GENERATE HTML TABLE 
          SELECT    @xml = CAST(
(
    SELECT [SPID] AS 'td',
           '',
           [Start_Time] AS 'td',
           '',
           [Duration] AS 'td',
           '',
           [Status] AS 'td',
           '',
           [LogIName] AS 'td',
           '',
           [HostName] AS 'td',
           '',
           [DB] AS 'td',
           '',
           [Query] AS 'td',
           '',
           [Text] AS 'td'
    FROM    [cte]
    WHERE  [Duration] > = @longrunningthreshold FOR XML PATH('tr'), ELEMENTS
) AS NVARCHAR(MAX));

-- step 3: do rest of html formatting
     SET @body = '<html>
             <body>
             <H2>Long Running Queries ( Limit > 2 Minute(s) ) </H2>
             <table border = 1 BORDERCOLOR="Black"> 
			 <tr>
			 <th align="centre"> SPID </th>
			 <th> Start_Time </th> 
			 <th> Duration(Min) </th> 
			 <th> Status </th>
			 <th> LogIName </th>
			 <th> HostName </th>
			 <th> DB </th> 
			 <th> Query </th>
			  <th> Text </th>
			 </tr>';

     SET @body = @body+@xml+'</table></body></html>';

-- STEP 4: SEND EMAIL IF A LONG RUNNING QUERY IS FOUND.
     IF(@xml IS NOT NULL)
         BEGIN
             EXEC [msdb].[dbo].[Sp_send_dbmail]
                  @profile_name = 'SQLAdmin',
                  @body = @body,
                  @body_format = 'HTML',
                  @recipients = @recipients,
                  @subject = @subject;
         END;
     RETURN(0);
GO
