RAISERROR('Create procedure: [dbo].[usp_jobExecutionSaveStatistics]', 10, 1) WITH NOWAIT
GO
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

if exists (select * from dbo.sysobjects where id = object_id(N'[dbo].[usp_jobExecutionSaveStatistics]') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
drop procedure [dbo].[usp_jobExecutionSaveStatistics]
GO

CREATE PROCEDURE [dbo].[usp_jobExecutionSaveStatistics]
		@projectCode			[varchar](32) = NULL,
		@moduleFilter			[varchar](32) = '%',
		@descriptorFilter		[varchar](256)= '%'
AS
SET NOCOUNT ON;

DECLARE   @projectID	[smallint]

------------------------------------------------------------------------------------------------------------------------------------------
--get default projectCode
IF @projectCode IS NULL
	SET @projectCode = [dbo].[ufn_getProjectCode](NULL, NULL)

SELECT @projectID = [id]
FROM [dbo].[catalogProjects]
WHERE [code] = @projectCode 

------------------------------------------------------------------------------------------------------------------------------------------
-- Delete existing information
DELETE jes 
FROM [dbo].[jobExecutionStatisticsHistory] AS jes
INNER JOIN dbo.[vw_jobExecutionStatistics] AS jesl ON	jes.[project_id] = jesl.[project_id]
													AND jes.[instance_id] = jesl.[instance_id]
													AND jes.[module] = jesl.[module]
													AND jes.[descriptor] = jesl.[descriptor]
													AND jes.[start_date] = jesl.[start_date]
													AND jes.[task_id] = jesl.[task_id]
WHERE	(jesl.[project_id] = @projectID OR @projectID IS NULL) 
		AND jesl.[module] LIKE @moduleFilter 
		AND jesl.[descriptor] LIKE @descriptorFilter

------------------------------------------------------------------------------------------------------------------------------------------
-- save up-to-date execution statistics
INSERT	INTO [dbo].[jobExecutionStatisticsHistory]([project_id], [instance_id], [module], [descriptor], [duration_minutes_parallel], [duration_minutes_serial], [start_date], [task_id], [status])
		SELECT	  jesl.[project_id]
				, jesl.[instance_id]
				, jesl.[module]
				, jesl.[descriptor]
				, COALESCE(jesl.[duration_minutes_parallel], 0)
				, COALESCE(jesl.[duration_minutes_serial], 0)
				, jesl.[start_date]
				, CASE WHEN jesl.[task_id] = -1 THEN NULL ELSE jesl.[task_id] END AS [task_id]
				, jesl.[status]
		FROM [dbo].[vw_jobExecutionStatistics] AS jesl
		LEFT JOIN [dbo].[jobExecutionStatisticsHistory] AS jes ON	jes.[project_id] = jesl.[project_id]
																AND jes.[instance_id] = jesl.[instance_id]
																AND jes.[module] = jesl.[module]
																AND jes.[descriptor] = jesl.[descriptor]
																AND jes.[start_date] = jesl.[start_date]
																AND jes.[task_id] = jesl.[task_id]
		WHERE	jes.[id] IS NULL 
				AND jesl.[start_date] IS NOT NULL 
				AND (jesl.[project_id] = @projectID OR @projectID IS NULL) 
				AND jesl.[module] LIKE @moduleFilter 
				AND jesl.[descriptor] LIKE @descriptorFilter
GO
