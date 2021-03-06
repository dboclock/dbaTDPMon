-- ============================================================================
-- Copyright (c) 2004-2018 Dan Andrei STEFAN (danandrei.stefan@gmail.com)
-- ============================================================================
-- Author			 : Razvan Puscasu
-- Create date		 : 
-- Module			 : Database Analysis & Performance Monitoring
-- ============================================================================

-----------------------------------------------------------------------------------------------------
--internal jobs execution statistics
-----------------------------------------------------------------------------------------------------
RAISERROR('Create table: [dbo].[jobExecutionStatisticsHistory]', 10, 1) WITH NOWAIT
GO
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[jobExecutionStatisticsHistory]') AND type in (N'U'))
DROP TABLE [dbo].[jobExecutionStatisticsHistory]
GO
CREATE TABLE [dbo].[jobExecutionStatisticsHistory]
(
	[id]						[int]	 IDENTITY (1, 1)	NOT NULL,
	[project_id]				[smallint]		NOT NULL,
	[instance_id]				[smallint]		NULL,
	[task_id]					[bigint]		NULL,
	[start_date]				[datetime]		NOT NULL,
	[module]					[varchar](32)	NOT NULL,
	[descriptor]				[varchar](256)	NOT NULL,
	[duration_minutes_parallel] [int]			NOT NULL CONSTRAINT [DF_jobExecutionStatisticsHistory_DurationMinutesParallel]  DEFAULT ((0)),
	[duration_minutes_serial]	[int]			NOT NULL CONSTRAINT [DF_jobExecutionStatisticsHistory_DurationMinutesSerial]  DEFAULT ((0)),
	[status]					[varchar](256)	NULL,
	CONSTRAINT [PK_jobExecutionStatisticsHistory] PRIMARY KEY CLUSTERED 
	(
		[id] ASC
	) ON [FG_Statistics_Data],
	CONSTRAINT [FK_jobExecutionStatisticsHistory_catalogProjects] FOREIGN KEY 
	(
		[project_id]
	) 
	REFERENCES [dbo].[catalogProjects] 
	(
		[id]
	),
	CONSTRAINT [FK_jobExecutionStatisticsHistory_catalogInstanceNames] FOREIGN KEY 
	(
		[instance_id],
		[project_id]
	) 
	REFERENCES [dbo].[catalogInstanceNames] 
	(
		[id],
		[project_id]
	)
) ON [FG_Statistics_Data]
GO

CREATE INDEX [IX_jobExecutionStatisticsHistory_ProjectID_TaskID] ON [dbo].[jobExecutionStatisticsHistory]([project_id], [task_id]) ON [FG_Statistics_Index]
GO
CREATE INDEX [IX_jobExecutionStatisticsHistory_Instance_ID_ProjectID] ON [dbo].[jobExecutionStatisticsHistory](instance_id, [project_id]) ON [FG_Statistics_Index]
GO
