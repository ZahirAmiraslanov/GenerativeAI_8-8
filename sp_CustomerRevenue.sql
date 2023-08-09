/****** Object:  StoredProcedure [dbo].[sp_CustomerRevenue]    Script Date: 8/9/2023 12:10:59 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER   PROCEDURE [dbo].[sp_CustomerRevenue]
(
    -- Add the parameters for the stored procedure here
    @FromYear int NULL,
    @Toyear int NULL,
	@Period varchar(1) NULL,
	@CustomerID int NULL
)
AS
BEGIN


    -- SET NOCOUNT ON added to prevent extra result sets from
    -- interfering with SELECT statements.
    SET NOCOUNT ON

	BEGIN TRY
	
	IF OBJECT_ID ('Errorlog') IS NULL
	CREATE TABLE Errorlog
       (
       [ErrorID] int, 
       [ErrorNumber] int,
       [ErrorSeverity] int, 
       [ErrorMessage] varchar(255),
       [CustomerID] int, 
       [Period] varchar(8),
       [CreatedAt] datetime
       )


	IF @FromYear IS NULL
	   BEGIN
	      SELECT @FromYear=MIN(YEAR(sale.[Invoice date key])) FROM [Fact].[Sale] sale
		END;

	IF @Toyear IS NULL
	   BEGIN
	      SELECT @Toyear=MAX(YEAR(sale.[Invoice date key])) FROM [Fact].[Sale] sale
		END;
	
	IF @Period IS NULL
	   BEGIN
	      SET  @Period='Y'
		END;

 

    -- Insert statements for procedure here

	--Create a table to insert the data

	DECLARE @CustomerName varchar(50)
	IF @CustomerID IS NOT NULL
	BEGIN
	SELECT @CustomerName= cust.Customer  FROM [Dimension].Customer cust
	END
	
	DECLARE @TableName NVARCHAR(MAX)
	SET @TableName=
	   '['+
	   CASE WHEN @CustomerID IS NULL THEN 'ALL' ELSE LTRIM(STR(@CustomerID))+'_'+@CustomerName END
	   +'_'+LTRIM(STR(@FromYear))
	   +CASE WHEN @Toyear=@FromYear THEN '' ELSE '_'+LTRIM(STR(@Toyear)) END
	   +'_'+LTRIM(@Period)
	   +']'
declare @SQL NVARCHAR(MAX)
SET @SQL='BEGIN '+ 'DROP TABLE IF EXISTS '+LTRIM(@TableName)+
' CREATE TABLE '+LTRIM(@TableName)+
'('+'[CustomerID] int, 
     [CustomerName] nvarchar(100),
     [Period] varchar(8), 
     [Revenue] numeric(19,2)
  )'
  +'END;'
 

EXEC sp_executesql  @SQL;


 --Prepare Revenue data
    
	SELECT
	   cust.[Customer Key] [CustomerId],
	   cust.Customer [CustomerName],
	   CASE
	      WHEN @Period='M' THEN dt.[Short Month]+LTRIM(STR(dt.[Calendar Year])) 
		  WHEN @Period='Y' THEN STR(dt.[Calendar Year])
		  WHEN @Period='Q' THEN 
		     CASE 
			    WHEN dt.[Calendar Month Number] IN (1,2,3)    THEN  'Q1'
				WHEN dt.[Calendar Month Number] IN (4,5,6)    THEN  'Q2'
				WHEN dt.[Calendar Month Number] IN (7,8,9)    THEN  'Q3'
				WHEN dt.[Calendar Month Number] IN (10,11,12) THEN  'Q4'
			END
				--'Q'+LTRIM(STR(CAST(CEILING(CAST(8 AS NUMERIC (5,2))/3) AS INT)))
			+' '+LTRIM(STR(dt.[Calendar Year])) 
	   END AS [Period],
	      
	   sale.[Quantity]*sale.[Unit Price] [Revenue]
	 INTO #tempdata
	FROM 
	     [Fact].Sale sale
	INNER JOIN
	   	 [Dimension].[Customer] cust
	ON
	     cust.[Customer Key]=sale.[Customer Key]
    INNER JOIN
	     [Dimension].Date dt 
	ON
	     sale.[Invoice Date Key]=dt.Date

	WHERE 
	   dt.[Calendar Year] BETWEEN @FromYear AND @Toyear
	AND
	   (@CustomerID IS NULL OR  cust.[Customer Key]=@CustomerID)
  
  DECLARE @affectedRows INT=0
  --Insert data into a table
  SET @SQL =
  'INSERT INTO '+LTRIM(@TableName)+' '+
  'SELECT 
      [CustomerId],
	  [CustomerName],
	  LTRIM([Period]),
	  SUM([Revenue]) [Revenue]
  FROM 
     #tempdata
  GROUP BY
      [CustomerId],
	  [CustomerName],
	  [Period]

	SET @affectedRows=@@rowcount
  '
  
  EXEC sp_executesql  @SQL,N'@affectedRows INT OUTPUT', @affectedRows = @affectedRows OUTPUT;
  SELECT 'SELECT * FROM '+ltrim(@TableName)

  SELECT @affectedRows;

  IF @affectedRows=0
    BEGIN
	   SET @SQL=
	  'INSERT INTO '+@TableName+
	  ' SELECT '+STR(@CustomerID)+', '+QUOTENAME(@CustomerName,'''')+', '+STR(@FromYear)+', '+ STR('0.00')
	   
	   EXEC sp_executesql  @SQL
	END;

	END TRY

	BEGIN CATCH
	   INSERT INTO 
	      ErrorLog
	   SELECT
	      @@ERROR ErrorID
	     ,ERROR_NUMBER() AS [ErrorNumber] 
         ,ERROR_SEVERITY() AS [ErrorSeverity] 
	     ,ERROR_MESSAGE() AS [ErrorMessage] 
	     ,CASE WHEN @CustomerID IS NULL THEN -1 ELSE @CustomerID END [CustomerID]
	     ,@FromYear [Period]
         ,GETUTCDATE() AS [CreatedAt] 
    END CATCH 
END


GO



