
---This procedure give the process for MONITORING BLOCKING



--1- Install SP_whoIsActive

--2-  Create tableDBA__whoisactive2  --this callect the information from sp_whoIsACTIVE and will be truncated every run

--3- Create Table CREATE TABLE [dbo].[DBA__Blocking_Audit] --this table keep the blocking informationfor analizing

--4--Create jobs in 3 steps  see bellow.   note. The two first step are most important, The 3 is more PagerDuty

USE [DBA]
GO

/****** Object:  Table [dbo].[DBA__Blocking_Audit]    Script Date: 12/1/2023 4:10:51 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DBA__Blocking_Audit](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[victim_id] [smallint] NOT NULL,
	[victim_sql] [xml] NULL,
	[Victim_wait] [varchar](8000) NULL,
	[victim_login] [nvarchar](128) NOT NULL,
	[Victim_Lock_type] [nvarchar](4000) NULL,
	[Victim_status] [varchar](30) NOT NULL,
	[Victim_host] [nvarchar](128) NULL,
	[Victim_DB] [nvarchar](128) NULL,
	[Victim_start] [nvarchar](128) NULL,
	[BLOCKER_id] [smallint] NOT NULL,
	[BLOCKER_sql] [xml] NULL,
	[BLOCKER_login] [nvarchar](128) NOT NULL,
	[BLOCKER_status] [varchar](30) NOT NULL,
	[BLOCKER_host] [nvarchar](128) NULL,
	[BLOCKER_start] [nvarchar](128) NULL,
	[TIMESTAMP] [datetime] NULL,
	[PD_Send] [nvarchar](100) NULL,
 CONSTRAINT [PK_DBA__Blocking_Audit] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO



 Create tableDBA__whoisactive2
*    ==Scripting Parameters==

    Source Server Version : SQL Server 2016 (13.0.4001)
    Source Database Engine Edition : Microsoft SQL Server Enterprise Edition
    Source Database Engine Type : Standalone SQL Server

    Target Server Version : SQL Server 2016
    Target Database Engine Edition : Microsoft SQL Server Enterprise Edition
    Target Database Engine Type : Standalone SQL Server
*/

USE [FLX_DBA]
GO

/****** Object:  Table [dbo].[DBA__whoisactive2]    Script Date: 12/1/2023 4:09:45 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DBA__whoisactive2](
	[dd hh:mm:ss.mss] [varchar](8000) NULL,
	[session_id] [smallint] NOT NULL,
	[sql_text] [xml] NULL,
	[login_name] [nvarchar](128) NOT NULL,
	[wait_info] [nvarchar](4000) NULL,
	[CPU] [varchar](30) NULL,
	[tempdb_allocations] [varchar](30) NULL,
	[tempdb_current] [varchar](30) NULL,
	[blocking_session_id] [smallint] NULL,
	[reads] [varchar](30) NULL,
	[writes] [varchar](30) NULL,
	[physical_reads] [varchar](30) NULL,
	[used_memory] [varchar](30) NULL,
	[status] [varchar](30) NOT NULL,
	[open_tran_count] [varchar](30) NULL,
	[percent_complete] [varchar](30) NULL,
	[host_name] [nvarchar](128) NULL,
	[database_name] [nvarchar](128) NULL,
	[program_name] [nvarchar](128) NULL,
	[start_time] [datetime] NOT NULL,
	[login_time] [datetime] NULL,
	[request_id] [int] NULL,
	[collection_time] [datetime] NOT NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO





--Step1 jobs

Truncate table [dbo].[DBA__whoisactive2] 

EXEC sp_WhoIsActive
    @destination_table = '[FLX_DBA].[dbo].[DBA__whoisactive2]'

--Step 2 jobs

IF EXISTS( SELECT * FROM [FLX_DBA].[dbo].[DBA__whoisactive2] WHERE blocking_session_id IS NOT NULL 
	   and 
	   [dd hh:mm:ss.mss] > '000 00:01:00.000'

)
begin
insert into [FLX_DBA]..[DBA__Blocking_Audit]
SELECT 
V.session_id as victim_id
,V.sql_text as victim_sql
,V.[dd hh:mm:ss.mss] as Victim_wait
,V.[login_name] as victim_login
,V.[wait_info] as Victim_Lock_type
,V.[status] as Victim_status
,V.[host_name] as Victim_host
,V.[database_name] as Victim_DB
,V.[start_time] as Victim_start
,B.session_id as BLOCKER_id
,B.sql_text as BLOCKER_sql
,B.[login_name] as BLOCKER_login
,B.[status] as BLOCKER_status
,B.[host_name] as BLOCKER_host
,B.[start_time] as BLOCKER_start
,Getdate()
,''

 FROM [FLX_DBA].[dbo].[DBA__whoisactive2] as V
 join [FLX_DBA].[dbo].[DBA__whoisactive2]as B ON B.session_ID = V.Blocking_session_ID
--where V.blocking_session_id = 493 and V.session_id =566
Where V.blocking_session_id is not null
and 
V.[dd hh:mm:ss.mss] > '000 00:01:00.000'


DECLARE @mydate datetime
DECLARE @server varchar(20)
DECLARE @msg varchar(200)
DECLARE @node varchar(50)
DECLARE @oper_email NVARCHAR(200)

SET @mydate = getdate()
SET @server = @@servername


SET @oper_email = ( SELECT  email_address
                    FROM    msdb.dbo.sysoperators
                    WHERE   name = 'DBAs'
                  )

SET @msg = 'BLOCK Alert:   '+ convert(varchar(100),serverproperty('machinename')) + ' has BLOCKINGS: GO to server and check table DBA_Blocking_Audit'

EXEC msdb.dbo.sp_send_dbmail @recipients = @oper_email, @body = @msg,
    @subject = @msg

END




----Step3 jobs

IF EXISTS(
select *
from [FLX_DBA]..[DBA__Blocking_Audit]
where victim_wait < '000 00:02:00.000'
and PD_Send <> 'YES'
and Victim_DB not in
(
'Distribution'
,'master'
,'msdb'
,'model'
))
	BEGIN


		DECLARE @mydate datetime
		DECLARE @server varchar(20)
		DECLARE @msg varchar(200)
		DECLARE @node varchar(50)
		DECLARE @oper_email NVARCHAR(200)

		SET @mydate = getdate()
		SET @server = @@servername

		--- TESTING
		SET @oper_email = ( SELECT  email_address
							FROM    msdb.dbo.sysoperators
							WHERE   name = 'DBAs'
						  )
		---- PAGER Duty
		SET @oper_email = 'sql.adapters.timeouts@farelogix.pagerduty.com'
		SET @msg = 'BLOCK Alert:   '+ convert(varchar(100),serverproperty('machinename')) + ' has BLOCKINGS: GO to server and check table DBA_Blocking_Audit'

		EXEC msdb.dbo.sp_send_dbmail @recipients = @oper_email, @body = @msg,
			@subject = @msg

		--- FLAG
		update [FLX_DBA]..[DBA__Blocking_Audit]
		set PD_Send = 'YES'
		where victim_wait < '000 00:02:00.000'
		and PD_Send <> 'YES'
		and Victim_DB not in
		(
			'Distribution'
			,'master'
			,'msdb'
			,'model'
		)

	END
