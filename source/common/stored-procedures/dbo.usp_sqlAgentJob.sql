RAISERROR('Create procedure: [dbo].[usp_sqlAgentJob]', 10, 1) WITH NOWAIT
GO
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

if exists (select * from dbo.sysobjects where id = object_id(N'[dbo].[usp_sqlAgentJob]') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
drop procedure [dbo].[usp_sqlAgentJob]
GO

CREATE PROCEDURE [dbo].[usp_sqlAgentJob]
		@sqlServerName			[sysname],
		@jobName				[sysname],
		@operation				[varchar](10), 
		@dbName					[sysname], 
		@jobStepName 			[sysname]='',
		@jobStepCommand			[varchar](8000)='',
		@jobLogFileName			[varchar](512)='',
		@jobStepRetries			[smallint]=0,
		@debugMode				[bit]=0
/* WITH ENCRYPTION */
AS
	
-- ============================================================================
-- Copyright (c) 2004-2015 Dan Andrei STEFAN (danandrei.stefan@gmail.com)
-- ============================================================================
-- Author			 : Dan Andrei STEFAN
-- Create date		 : 2004-2014
-- Module			 : Database Analysis & Performance Monitoring
-- ============================================================================

------------------------------------------------------------------------------------------------------------------------------------------
--		@jobName		- numele job-ului... toate operatiunile se vor face functie de acest nume!
--		@operation		'Add'   - se adauga un nou step definit de @jobStepName si @jobStepCommand
--						'Clean' - curata job-ul de pasi si sterge job-ul
--						'Stop'
--		@dbName			- baza de date pentru care este asociat job-ul
--		@jobStepName	- numele pasului ce se adauga
--		@jobStepCommand	- script sql ce se va executa pentru pasul definit
------------------------------------------------------------------------------------------------------------------------------------------

DECLARE @Error				[int],
		@jobID 				[varchar](200),
		@jobStepID			[int],
		@jobStepIDNew		[int],
		@jobCategoryID		[int],
		@jobStepStatus		[int], 
		@queryToRun			[nvarchar](4000),
		@queryParameters	[nvarchar](512),
		@tmpServer			[varchar](8000),
		@jobCurrentRunning	[bit]

DECLARE	  @serverEdition			[sysname]
		, @serverVersionStr			[sysname]
		, @serverVersionNum			[numeric](9,6)
		, @nestedExecutionLevel		[tinyint]

---------------------------------------------------------------------------------------------
SET NOCOUNT ON
---------------------------------------------------------------------------------------------

IF object_id('#tmpCheckParameters') IS NOT NULL DROP TABLE #tmpCheckParameters
CREATE TABLE #tmpCheckParameters (Result varchar(1024))

IF ISNULL(@sqlServerName, '')=''
	begin
		SET @queryToRun='ERROR: The specified value for SOURCE server is not valid.'
		EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=1
		RETURN 1
	end

IF LEN(@jobName)=0 OR ISNULL(@jobName, '')=''
	begin
		SET @queryToRun='ERROR: Must specify a job name.'
		EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=1
		RETURN 1
	end

SET @queryToRun='SELECT [srvid] FROM master.dbo.sysservers WHERE [srvname]=''' + @sqlServerName + ''''
TRUNCATE TABLE #tmpCheckParameters
INSERT INTO #tmpCheckParameters EXEC sp_executesql  @queryToRun
IF (SELECT count(*) FROM #tmpCheckParameters)=0
	begin
		SET @queryToRun='ERROR: SOURCE server [' + @sqlServerName + '] is not defined as linked server on THIS server [' + @sqlServerName + '].'
		EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=1
		RETURN 1
	end

SET @tmpServer = '[' + @sqlServerName + '].master.dbo.sp_executesql'

------------------------------------------------------------------------------------------------------------------------------------------
--get destination server running version/edition
EXEC [dbo].[usp_getSQLServerVersion]	@sqlServerName		= @sqlServerName,
										@serverEdition		= @serverEdition OUT,
										@serverVersionStr	= @serverVersionStr OUT,
										@serverVersionNum	= @serverVersionNum OUT,
										@executionLevel		= 0,
										@debugMode			= @debugMode


------------------------------------------------------------------------------------------------------------------------------------------
--adding a new job or step to the existing job
IF @operation='Add'
	begin
		SET @queryToRun='SELECT category_id FROM msdb.dbo.syscategories WHERE name LIKE ''%Database Maintenance%'''
		SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
		IF @debugMode = 1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

		TRUNCATE TABLE #tmpCheckParameters
		INSERT INTO #tmpCheckParameters EXEC sp_executesql  @queryToRun
		SELECT TOP 1 @jobCategoryID=Result FROM #tmpCheckParameters

		SET @jobStepID=1

		SET @queryToRun='SELECT count(*) FROM msdb.dbo.sysjobs WHERE name = ''' + [dbo].[ufn_getObjectQuoteName](@jobName, 'sql') + ''''
		SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
		IF @debugMode = 1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

		TRUNCATE TABLE #tmpCheckParameters
		INSERT INTO #tmpCheckParameters EXEC sp_executesql  @queryToRun
		
		--defining job and job properties
		IF (SELECT ISNULL(Result,0) FROM #tmpCheckParameters) =0
			begin
				--adding job
				set @queryToRun='EXEC msdb.dbo.sp_add_job 	@enabled 	 = 1, 
															@job_name	 = ''' + [dbo].[ufn_getObjectQuoteName](@jobName, 'sql') + ''', 
															@description = ''' + [dbo].[ufn_getObjectQuoteName](@jobName, 'sql') + ''', 
															@category_id = ' + CAST(@jobCategoryID as varchar) + ', 
															@owner_login_name = ''sa'''
				IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0
				EXEC @Error=@tmpServer @queryToRun

				IF @Error<>0
					begin
						SET @queryToRun='Cannot add job ' + @jobName + ' to SQL Server Agent.'
						EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=1
						RETURN 1
					end

				--adding job to server
				SET @queryToRun='EXEC msdb.dbo.sp_add_jobserver @job_name = ''' + [dbo].[ufn_getObjectQuoteName](@jobName, 'sql') + ''', @server_name = ''(local)'''
				IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0
				EXEC @Error=@tmpServer @queryToRun

				IF @Error<>0
					begin
						SET @queryToRun='Cannot add job ' + @jobName + ' to SQL Server Agent.'
						EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=1
						RETURN 1
					end
				ELSE
					begin
						SET @queryToRun='Successfully add job ' + @jobName + ' to SQL Server Agent.'
						EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=0
					end
		
			end
		SET @queryToRun='SELECT job_id FROM msdb.dbo.sysjobs WHERE name = ''' + [dbo].[ufn_getObjectQuoteName](@jobName, 'sql') + ''''
		SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
		IF @debugMode = 1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

		TRUNCATE TABLE #tmpCheckParameters
		INSERT INTO #tmpCheckParameters EXEC sp_executesql  @queryToRun
		SELECT TOP 1 @jobID = ISNULL(Result,'') FROM #tmpCheckParameters

		SET @queryToRun='SELECT TOP 1 (step_id+1) FROM msdb.dbo.sysjobsteps WHERE job_id=''' + @jobID + ''' ORDER BY step_id DESC'
		SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
		IF @debugMode = 1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

		TRUNCATE TABLE #tmpCheckParameters
		INSERT INTO #tmpCheckParameters EXEC sp_executesql  @queryToRun
		SELECT TOP 1 @jobStepID = ISNULL(Result,0) FROM #tmpCheckParameters

		IF @jobStepID-1>0
			begin
				SET @queryToRun='UPDATE msdb.dbo.sysjobsteps SET on_success_action=4, on_success_step_id=' + CAST(@jobStepID as varchar) + ', on_fail_action=4, on_fail_step_id=' + CAST(@jobStepID as varchar) + ' WHERE job_id=''' + @jobID + ''' AND step_id=' + CAST((@jobStepID-1) as varchar) 
				IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0
				EXEC @tmpServer @queryToRun				
			end

		--defining job step and step properties
		SET @queryToRun='EXEC msdb.dbo.sp_add_jobstep	@job_id = ''' + @jobID + ''',
														@step_id = ' + CAST(@jobStepID as varchar) + ',
														@step_name = ''' + [dbo].[ufn_getObjectQuoteName](@jobStepName, 'sql') + ''',
														@on_success_action = 1,
														@on_fail_action = 2, 
														@retry_interval = 1,							
														@command = ''' + @jobStepCommand + ''',
														@database_name = ''' + [dbo].[ufn_getObjectQuoteName](@dbName, 'sql') + ''','
		IF @jobLogFileName<>'' 
			SET @queryToRun=@queryToRun + '
								@output_file_name=''' + [dbo].[ufn_getObjectQuoteName](@jobLogFileName, 'filepath') + ''','
		SET @queryToRun=@queryToRun + '				
								@retry_attempts=' + CAST(@jobStepRetries AS [varchar]) + ',
								@flags=6'
		
		IF @debugMode=1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0
		EXEC @tmpServer @queryToRun

		IF @Error<>0
			begin
				SET @queryToRun= 'Cannot add job step: ' + [dbo].[ufn_getObjectQuoteName](@jobStepName, 'quoted') + ' to server job ' + @jobName
				EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=1
				RETURN 1
			end
		ELSE
			begin
				SET @queryToRun= 'Successfully add job step: ' + [dbo].[ufn_getObjectQuoteName](@jobStepName, 'quoted') + ' to server job ' + @jobName
				EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=0
			end
	end
------------------------------------------------------------------------------------------------------------------------------------------
--erase all job steps
IF @operation='Clean'
	begin
		EXEC [dbo].[usp_sqlAgentJobCheckStatus] @sqlServerName, @jobName, '', @jobCurrentRunning OUT, '', '', '', 0, 0, 0, 0
		IF @jobCurrentRunning=1
			begin
				IF @debugMode=1 
					begin 
						SET @queryToRun='Debug info: @sqlServerName=' + @sqlServerName + '; @jobName=' + @jobName + '; @jobCurrentRunning=' + CAST(@jobCurrentRunning AS [varchar]);
						EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=0
					end

				SET @queryToRun='Cannot delete a job while it is running.'
				EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=0

				------------------------------------------------------------------------------------------------------------------------------------------
				SET @queryToRun='Stopping...'
				EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=0

				DECLARE   @configMaxNumberOfRetries	[smallint]
						, @retryAttempts			[tinyint]

				SELECT	@configMaxNumberOfRetries = [value]
				FROM	[dbo].[appConfigurations]
				WHERE	[name] = N'Maximum number of retries at failed job'
						AND [module] = 'common'

				SET @configMaxNumberOfRetries = ISNULL(@configMaxNumberOfRetries, 3)

				EXEC [dbo].[usp_sqlAgentJob]	@sqlServerName	= @sqlServerName,
												@jobName		= @jobName,
												@operation		= 'Stop',
												@dbName			= @dbName, 
												@jobStepName 	= @jobStepName,
												@debugMode		= @debugMode

				SET @retryAttempts = 1
				WHILE @jobCurrentRunning = 1 AND @retryAttempts <= @configMaxNumberOfRetries
					begin
						WAITFOR DELAY '00:00:01'

						SET @jobCurrentRunning = 0
						EXEC  dbo.usp_sqlAgentJobCheckStatus	@sqlServerName			= @sqlServerName,
																@jobName				= @jobName,
																@strMessage				= DEFAULT,	
																@currentRunning			= @jobCurrentRunning OUTPUT,			
																@lastExecutionStatus	= DEFAULT,			
																@lastExecutionDate		= DEFAULT,		
																@lastExecutionTime 		= DEFAULT,	
																@runningTimeSec			= DEFAULT,
																@selectResult			= DEFAULT,
																@extentedStepDetails	= DEFAULT,		
																@debugMode				= DEFAULT
						
						SET @retryAttempts = @retryAttempts + 1
					end
			end

		SET @queryToRun='SELECT job_id FROM msdb.dbo.sysjobs WHERE name = ''' + [dbo].[ufn_getObjectQuoteName](@jobName, 'sql') + ''''
		SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
		IF @debugMode = 1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

		TRUNCATE TABLE #tmpCheckParameters
		INSERT INTO #tmpCheckParameters EXEC sp_executesql  @queryToRun
		SELECT TOP 1 @jobID = ISNULL(Result,'') FROM #tmpCheckParameters

		SET @queryToRun='SELECT count(*) FROM msdb.dbo.sysjobsteps WHERE job_id=''' + @jobID + ''''
		SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
		IF @debugMode = 1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

		TRUNCATE TABLE #tmpCheckParameters
		INSERT INTO #tmpCheckParameters EXEC sp_executesql  @queryToRun
		
		WHILE (SELECT Result FROM #tmpCheckParameters)<>0
			begin
				SET @queryToRun='SELECT step_id FROM msdb.dbo.sysjobsteps WHERE job_id=''' + @jobID + ''' ORDER BY step_id ASC'
				SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
				IF @debugMode = 1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

				TRUNCATE TABLE #tmpCheckParameters
				INSERT INTO #tmpCheckParameters EXEC sp_executesql  @queryToRun

				DECLARE JobSteps CURSOR FOR SELECT Result FROM #tmpCheckParameters
				OPEN JobSteps
				FETCH NEXT FROM JobSteps INTO @jobStepID
				WHILE @@FETCH_STATUS=0
					begin
						SET @queryToRun='EXEC msdb.dbo.sp_delete_jobstep @job_id=''' + @jobID + ''', @step_id=1'
						IF @debugMode=1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

						EXEC @Error=@tmpServer @queryToRun
						IF @Error<>0
							begin
								SET @queryToRun= 'Cannot delete job step ' + @jobName + ', StepID [' + CAST(@jobStepID AS varchar) + ']'
								EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=1
								CLOSE JobSteps
								DEALLOCATE JobSteps
								RETURN 1
							end							
						FETCH NEXT FROM JobSteps INTO @jobStepID
					end
				CLOSE JobSteps
				DEALLOCATE JobSteps
				SET @queryToRun='SELECT count(*) FROM msdb.dbo.sysjobsteps WHERE job_id=''' + @jobID + ''''
				SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
				IF @debugMode = 1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

				TRUNCATE TABLE #tmpCheckParameters
				INSERT INTO #tmpCheckParameters EXEC sp_executesql  @queryToRun
			end

		SET @queryToRun='SELECT count(*) FROM msdb.dbo.sysjobsteps WHERE job_id=''' + @jobID + ''''
		SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
		IF @debugMode = 1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

		TRUNCATE TABLE #tmpCheckParameters
		INSERT INTO #tmpCheckParameters EXEC sp_executesql  @queryToRun

		IF (SELECT Result FROM #tmpCheckParameters)=0
			begin
				SET @queryToRun='SELECT count(*) FROM msdb.dbo.sysjobs WHERE job_id=''' + @jobID + ''''
				SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
				IF @debugMode = 1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

				TRUNCATE TABLE #tmpCheckParameters
				INSERT INTO #tmpCheckParameters EXEC sp_executesql  @queryToRun

				IF (SELECT Result FROM #tmpCheckParameters)<>0
					begin
						SET @queryToRun='EXEC msdb.dbo.sp_delete_job @job_id=''' + @jobID + ''', @delete_history=0'
						IF @debugMode=1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

						BEGIN TRY
							EXEC @Error=@tmpServer @queryToRun
							IF @Error<>0
								begin
									SET @queryToRun= 'Cannot delete job ' + @jobName
									EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=1
									RETURN 1
								end		
							SET @queryToRun= 'Successfully deleted job : ' + @jobName
							EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=0
						END TRY
						BEGIN CATCH
							SET @queryToRun= ERROR_MESSAGE()
							EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=1
							RETURN 1
						END CATCH
					end
			end
		ELSE
			begin
				SET @queryToRun= 'The specified job: ' + @jobName + ' does not exist on the server.'
				EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=0
			end
	end


------------------------------------------------------------------------------------------------------------------------------------------
--stop job
IF @operation='Stop'
	begin
		/* get the job_id */
		SET @queryToRun='SELECT job_id FROM msdb.dbo.sysjobs WHERE name = ''' + [dbo].[ufn_getObjectQuoteName](@jobName, 'sql') + ''''
		SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
		IF @debugMode = 1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

		TRUNCATE TABLE #tmpCheckParameters
		INSERT INTO #tmpCheckParameters EXEC sp_executesql  @queryToRun
		SELECT TOP 1 @jobID = [Result] FROM #tmpCheckParameters
				
		IF @jobID IS NULL 
			begin
				SET @queryToRun= 'The specified job: ' + @jobName + ' does not exist on the server.'
				EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=0
			end
		ELSE
			begin
				/* check if the job is running. if so, will stop it */ 
				SET @queryToRun = NULL
				IF @serverVersionNum < 10
					begin
						SET @jobCurrentRunning = 0
						EXEC [dbo].[usp_sqlAgentJobCheckStatus] @sqlServerName, @jobName, '', @jobCurrentRunning OUT, '', '', '', 0, 0, 0, 0
		
						IF @jobCurrentRunning=1
								SET @queryToRun = N'EXEC msdb.dbo.sp_stop_job @job_id=''' + @jobID + N''''
					end
				ELSE
					begin
						SET @queryToRun=N'IF EXISTS (
													SELECT	j.[name] 
													FROM  [msdb].[dbo].[sysjobactivity] ja WITH (NOLOCK)
													LEFT  JOIN [msdb].[dbo].[sysjobhistory] jh WITH (NOLOCK) ON ja.[job_history_id] = jh.[instance_id]
													INNER JOIN [msdb].[dbo].[sysjobs] j WITH (NOLOCK) ON ja.[job_id] = j.[job_id]
													INNER JOIN [msdb].[dbo].[sysjobsteps] js WITH (NOLOCK) ON ja.[job_id] = js.[job_id] AND ISNULL(ja.[last_executed_step_id], 0)+ 1  = js.[step_id]
													WHERE	ja.[session_id] = (
																				SELECT TOP 1 [session_id] 
																				FROM [msdb].[dbo].[syssessions] 
																				ORDER BY [agent_start_date] DESC
																				)
															AND ja.[start_execution_date] IS NOT NULL
															AND ja.[stop_execution_date] IS NULL
															AND j.[job_id]=''' + @jobID + N'''
													)
											EXEC msdb.dbo.sp_stop_job @job_id=''' + @jobID + N''''
					end

				IF @queryToRun IS NOT NULL
					begin
						IF @debugMode=1 EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = 0, @messageTreelevel = 1, @stopExecution=0

						BEGIN TRY
							EXEC @Error=@tmpServer @queryToRun
							IF @Error<>0
								begin
									SET @queryToRun= 'Cannot stop job ' + @jobName
									EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=0
								end		
							SET @queryToRun= 'Successfully stopped job : ' + @jobName
							EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=0
						END TRY
						BEGIN CATCH
							SET @queryToRun= ERROR_MESSAGE()
							EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = 1, @messageTreelevel = 1, @stopExecution=0
						END CATCH
					end
			end
	end

RETURN 0

GO
SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO

