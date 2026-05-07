USE AdventureWorks
GO

--------------------------------------------------------------------------------------------------------------------------- 

-- Create the Auction Schema if it doesn't already exist --

-- Check whether the Auction Schema already exists to keep script idempotent --

IF NOT EXISTS 
(
    SELECT 1 
    FROM sys.schemas 
    WHERE name = 'Auction'
)
EXEC('CREATE SCHEMA Auction')
GO

--------------------------------------------------------------------------------------------------------------------------- 

-- Create the AuctionPeriods table to store auction campaign time windows --

-- It is assumed that, when the campaign ends, the Active flag is manually updated to 0 --

IF NOT EXISTS 
(
    SELECT 1 
    FROM sys.tables AS t JOIN sys.schemas AS s ON t.schema_id = s.schema_id
    WHERE t.name = 'AuctionPeriods' AND s.name = 'Auction'
)

BEGIN
    CREATE TABLE Auction.AuctionPeriods
    (
        PeriodID            INT         NOT NULL IDENTITY(1,1),
        AuctionStartDate    DATETIME    NOT NULL,
        AuctionEndDate      DATETIME    NOT NULL,
        Active              BIT         NOT NULL DEFAULT 1,
   
        CONSTRAINT PK_AuctionPeriod PRIMARY KEY(PeriodID),
        CONSTRAINT CK_AuctionPeriods_Dates CHECK (AuctionEndDate > AuctionStartDate)
    );
      
END

--------------------------------------------------------------------------------------------------------------------------- 

-- Create an unique filtered index to guarantee that only one auction period can be active at a time -- 

IF NOT EXISTS 
(
    SELECT 1
    FROM sys.indexes
    WHERE name = 'UX_AuctionPeriods_OnlyOneActive' AND object_id = OBJECT_ID('Auction.AuctionPeriods')
)
BEGIN
    CREATE UNIQUE INDEX UX_AuctionPeriods_OnlyOneActive
    ON Auction.AuctionPeriods(Active)
    WHERE Active = 1;
END
GO

--------------------------------------------------------------------------------------------------------------------------- 

-- Insert Auction campaign Start and End Date into AuctionPeriods table -- 

IF NOT EXISTS 
(
    SELECT 1 
    FROM Auction.AuctionPeriods 
    WHERE AuctionStartDate = '2026-11-16 00:00:00' AND AuctionEndDate = '2026-11-30 23:59:59'
)

BEGIN  
    INSERT INTO Auction.AuctionPeriods (AuctionStartDate, AuctionEndDate, Active)
    VALUES ('2026-11-16 00:00:00', '2026-11-30 23:59:59', 1);
END

--------------------------------------------------------------------------------------------------------------------------- 

-- Create the Configuration table to store global auction parameters --

IF NOT EXISTS 
(
    SELECT 1 
    FROM sys.tables AS t JOIN sys.schemas AS s ON t.schema_id = s.schema_id
    WHERE t.name = 'Configuration' AND s.name = 'Auction'
)

BEGIN
    CREATE TABLE Auction.Configuration
    (
        ParameterId     INT             NOT NULL IDENTITY(1,1),
        ParameterName   NVARCHAR(50)    NOT NULL,
        ParameterValue  DECIMAL(10,2)   NOT NULL,
        Active          BIT             NOT NULL DEFAULT 1,

         CONSTRAINT PK_Configuration PRIMARY KEY(ParameterID),
         CONSTRAINT UQ_Configuration_ParameterName UNIQUE(ParameterName)
    );
END

--------------------------------------------------------------------------------------------------------------------------- 

--Insert parameter 'MinBidIncrement' into configuration table in case it doesn't exist --

IF NOT EXISTS 
(   
    SELECT 1 
    FROM Auction.Configuration 
    WHERE ParameterName = 'MinBidIncrement'
)

BEGIN  
    INSERT INTO Auction.Configuration (ParameterName, ParameterValue)
    VALUES ('MinBidIncrement', 0.05);
END

--------------------------------------------------------------------------------------------------------------------------- 

--Insert parameter 'MaxPriceMultiplier' into configuration table in case it doesn't exist --

IF NOT EXISTS 
(
    SELECT 1   
    FROM Auction.Configuration  
    WHERE ParameterName = 'MaxPriceMultiplier'
)

BEGIN  
    INSERT INTO Auction.Configuration (ParameterName, ParameterValue)
    VALUES ('MaxPriceMultiplier', 1);
END

--------------------------------------------------------------------------------------------------------------------------- 

-- Table that stores all possible auction status --

IF NOT EXISTS 
(
    SELECT 1 
    FROM sys.tables AS t JOIN sys.schemas AS s ON t.schema_id = s.schema_id
    WHERE t.name = 'AuctionStatus' AND s.name = 'Auction'
)

BEGIN
    CREATE TABLE Auction.AuctionStatus
    (
        AuctionStatusID     INT             NOT NULL IDENTITY(1,1),
        StatusDescription   NVARCHAR(50)    NOT NULL,

        CONSTRAINT PK_AuctionsStatus PRIMARY KEY(AuctionStatusID),
        CONSTRAINT UQ_AuctionStatus_StatusDescription UNIQUE(StatusDescription)
    );
END

--------------------------------------------------------------------------------------------------------------------------- 

-- Insert all possible auction status in case the table is empty --

IF NOT EXISTS 
(
    SELECT 1 
    FROM Auction.AuctionStatus
)

BEGIN
    INSERT INTO Auction.AuctionStatus (StatusDescription)
    VALUES ('ONGOING'), ('CANCELLED'), ('EXPIRED'), ('SOLD');
END

--------------------------------------------------------------------------------------------------------------------------- 

-- Create the Auctions table to store the products listed for auction --

IF NOT EXISTS 
(
    SELECT 1 
    FROM sys.tables AS t JOIN sys.schemas AS s ON t.schema_id = s.schema_id
    WHERE t.name = 'Auctions' AND s.name = 'Auction'
)

BEGIN
    CREATE TABLE Auction.Auctions
    (
        AuctionID           INT         NOT NULL IDENTITY(1,1), 
        ProductID           INT         NOT NULL,
        AuctionStatusID     INT         NOT NULL,
        IsActive            BIT         NOT NULL DEFAULT 1,     -- Default value is 1 to keep consistency with the AuctionStatusID -- 
        StartDate           DATETIME    NOT NULL,
        EndDate             DATETIME    NULL,
        ExpireDate          DATETIME    NOT NULL,
        InitialBidPrice     MONEY       NOT NULL,
        CurrentBidPrice     MONEY       NULL,

        CONSTRAINT PK_Auctions PRIMARY KEY(AuctionID),
        CONSTRAINT FK_Auctions_Product FOREIGN KEY(ProductID) 
            REFERENCES Production.Product(ProductID),
        CONSTRAINT FK_Auctions_AuctionStatus FOREIGN KEY(AuctionStatusID) 
            REFERENCES Auction.AuctionStatus(AuctionStatusID),
        CONSTRAINT CK_Auctions_Valid_StartDate CHECK (StartDate < ExpireDate),
        CONSTRAINT CK_Auctions_Valid_EndDate CHECK (EndDate IS NULL OR EndDate >= StartDate),
        CONSTRAINT CK_Auctions_InitialBidPrice_Positive CHECK (InitialBidPrice > 0)
    );
END
GO

--------------------------------------------------------------------------------------------------------------------------- 

-- Create a unique filtered index to ensure that each product can only have one active auction at a time --

IF NOT EXISTS 
(
    SELECT 1
    FROM sys.indexes
    WHERE name = 'UX_Auctions_Product_Active' AND object_id = OBJECT_ID('Auction.Auctions')
)
BEGIN
    CREATE UNIQUE INDEX UX_Auctions_Product_Active
    ON Auction.Auctions(ProductID)
    WHERE IsActive = 1;
END
GO

--------------------------------------------------------------------------------------------------------------------------- 

-- Create the Bids table to store all bids placed by customers --

IF NOT EXISTS 
(
    SELECT 1 
    FROM sys.tables AS t JOIN sys.schemas AS s ON t.schema_id = s.schema_id
    WHERE t.name = 'Bids' AND s.name = 'Auction'
)

BEGIN
    CREATE TABLE Auction.Bids
    (
        BidID       INT         NOT NULL IDENTITY(1,1),
        CustomerID  INT         NOT NULL,
        AuctionID   INT         NOT NULL,
        BidAmount   MONEY       NOT NULL,
        BidDate     DATETIME    NOT NULL DEFAULT GETDATE(),

        CONSTRAINT PK_Bids PRIMARY KEY(BidID),
        CONSTRAINT FK_Bids_Customer FOREIGN KEY(CustomerID) 
            REFERENCES Sales.Customer(CustomerID),
        CONSTRAINT FK_Bids_Auctions FOREIGN KEY(AuctionID) 
            REFERENCES Auction.Auctions(AuctionID),
        CONSTRAINT CK_Bids_BidAmount CHECK (BidAmount > 0)
    );
END
GO

--------------------------------------------------------------------------------------------------------------------------- 

-- Stored Procedures --

--------------------------------------------------------------------------------------------------------------------------- 

-- 1) uspAddProductToAuction Procedure: adds a product to an active auction campaign --

CREATE OR ALTER PROCEDURE Auction.uspAddProductToAuction
    @ProductID INT,
    @ExpireDate DATETIME = NULL, 
    @InitialBidPrice MONEY = NULL
AS 
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Declare Variables used to validate the product, campaign period, status and pricing rules --

        DECLARE @MakeFlag BIT;
        DECLARE @ListPrice MONEY;
        DECLARE @SellEndDate DATETIME;
        DECLARE @DiscontinuedDate DATETIME;
        DECLARE @AuctionStatusID INT;
        DECLARE @StartDate DATETIME;
        DECLARE @AuctionStartDate DATETIME;
        DECLARE @AuctionEndDate DATETIME;
        DECLARE @IsActive BIT;
        DECLARE @MaxPriceMultiplier DECIMAL(10,2);

        -- Checks whether the product exists in the Production.Product table --

        IF NOT EXISTS 
        (
            SELECT 1 
            FROM Production.Product AS p 
            WHERE p.ProductID = @ProductID
        )
        BEGIN                                                                              
            ;THROW 50001, 'Product does not exist. Is not eligible for auction.', 1;                                          
        END

        -- Retrieve product data required to validate auction eligibility and calculate the initial bid price --

        SELECT
            @MakeFlag = p.MakeFlag,
            @ListPrice = p.ListPrice,
            @SellEndDate = p.SellEndDate,
            @DiscontinuedDate = p.DiscontinuedDate
        FROM Production.Product AS p
        WHERE p.ProductID = @ProductID;

        -- Retrieve the active auction campaign period. The unique filtered index guarantees that only one active period can exist --

        SELECT
            @AuctionStartDate = AuctionStartDate,
            @AuctionEndDate = AuctionEndDate
        FROM Auction.AuctionPeriods
        WHERE Active = 1;

        -- Checks if the product is currently available for sale --

        IF @SellEndDate IS NOT NULL OR @DiscontinuedDate IS NOT NULL 
        BEGIN 
            ;THROW 50002, 'Product is no longer available for sale. Is not eligible for auction.', 1;                                          -- ; because Throw expects ; before or returns an error
        END

        -- Checks if the List Price variable has a valid value --

        IF @ListPrice IS NULL OR @ListPrice = 0
        BEGIN 
            ;THROW 50003, 'Product is missing a valid list price. Is not eligible for auction. ', 1;                                          -- ; because Throw expects ; before or returns an error
        END

        -- Ensure that there is an active auction campaign period before adding products to auction --

        IF @AuctionStartDate IS NULL OR @AuctionEndDate IS NULL
        BEGIN
            ;THROW 50004, 'Auction period is not active.', 1;
        END

        -- Use the current date and time as the auction start date --

        SET @StartDate = GETDATE();

        -- Ensure that products can only be added during the active auction campaign window --

        IF @StartDate < @AuctionStartDate OR @StartDate > @AuctionEndDate
        BEGIN
            ;THROW 50005, 'Product can only be added during the active auction campaign period.', 1;
        END

        -- Retrieve the ONGOING status and mark the new auction as active --

        DECLARE @ongoingID INT = 
        (
            SELECT AuctionStatusID 
            FROM Auction.AuctionStatus 
            WHERE StatusDescription = 'ONGOING'
        );

        SET @AuctionStatusID = @ongoingID;
        SET @IsActive = 1;

        -- Prevent the same product from being listed in more than one active auction --

        IF EXISTS 
        (
            SELECT 1
            FROM Auction.Auctions
            WHERE ProductID = @ProductID AND IsActive = 1
        )
        BEGIN
            ;THROW 50006, 'Product is already in an active auction.', 1;
        END

        -- If the expired date is not given than set one week from startdate --

        IF @ExpireDate IS NULL
        BEGIN
            SET @ExpireDate = DATEADD(WEEK, 1, @StartDate);  -- Default to one week from start date --
        END

        -- Validate that the expiration date is later than the auction start date --

        IF @ExpireDate <= @StartDate
        BEGIN
            ;THROW 50007, 'Expire date must be later than start date.', 1;
        END

        -- Ensure that the product auction expires within the active campaign period --

        IF @ExpireDate > @AuctionEndDate
        BEGIN
            ;THROW 50008, 'Expire date must be within the active auction campaign period.', 1;
        END

        -- If the InitialBidPrice is not given then set it based on MakeFlag --

        IF @InitialBidPrice IS NULL
        BEGIN
            -- Determine InitialBidPrice based on MakeFlag --

            IF @MakeFlag = 0  
            BEGIN
                SET @InitialBidPrice = @ListPrice * 0.75; 
            END
            ELSE  
            BEGIN
                SET @InitialBidPrice = @ListPrice * 0.50;  
            END
        END

        -- Retrieve the configured maximum price multiplier used to validate the initial bid price --

        SELECT @MaxPriceMultiplier = ParameterValue
        FROM Auction.Configuration
        WHERE ParameterName = 'MaxPriceMultiplier' AND Active = 1;

        SET @MaxPriceMultiplier = ISNULL(@MaxPriceMultiplier, 1);

        -- Checks if InitialBidPrice exceeds the list price --

        IF @InitialBidPrice > @ListPrice * @MaxPriceMultiplier
        BEGIN
            ;THROW 50009, 'The initial bid price must not exceed the configured maximum allowed price.', 1;
        END

        -- Begin transaction -- 

        BEGIN TRANSACTION;

        -- Insert the product into the auction list. CurrentBidPrice starts as NULL because no bid has been placed yet --

        INSERT INTO Auction.Auctions(ProductID, AuctionStatusID, IsActive, StartDate, EndDate, ExpireDate, InitialBidPrice, CurrentBidPrice)
        VALUES (@ProductID, @AuctionStatusID, @IsActive, @StartDate, NULL, @ExpireDate, @InitialBidPrice, NULL);

        -- Commit the transaction after the auction is successfully created -- 

        COMMIT;

        SELECT 'Product was successfully listed for auction.' AS SuccessMessage;

    END TRY
    BEGIN CATCH
        -- Roll back any open transaction before rethrowing the original error --

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
GO

---------------------------------------------------------------------------------------------------------------------------

-- 2) uspRemoveProductFromAuction Procedure: cancels an active auction for a given product --

CREATE OR ALTER PROCEDURE Auction.uspRemoveProductFromAuction
    @ProductID INT
AS
BEGIN
    SET NOCOUNT ON;  

    BEGIN TRY
        -- Retrieve the CANCELLED status identifier --

        DECLARE @cancelledID INT = 
        (
            SELECT AuctionStatusID 
            FROM Auction.AuctionStatus 
            WHERE StatusDescription = 'CANCELLED'
        );

        -- Begin transaction -- 

        BEGIN TRANSACTION;

        -- Mark the auction as cancelled and inactive while keeping its historical records --

        UPDATE Auction.Auctions
        SET AuctionStatusID = @cancelledID,
            IsActive = 0,
            EndDate = GETDATE()
        WHERE ProductID = @ProductID AND IsActive = 1;

        -- If no active auction was updated, the product is not currently listed for auction --

        IF @@ROWCOUNT = 0
        BEGIN
            ;THROW 50010, 'Product is not currently listed for auction.', 1;
        END

        COMMIT;

        SELECT 'Product auction was cancelled successfully.' AS SuccessMessage;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
GO

---------------------------------------------------------------------------------------------------------------------------

-- 3) uspUpdateProductAuctionStatus Procedure: updates expired active auctions to EXPIRED status --

CREATE OR ALTER PROCEDURE Auction.uspUpdateProductAuctionStatus
AS
BEGIN
    SET NOCOUNT ON;  

    BEGIN TRY
        DECLARE @ongoingID INT = 
        (
            SELECT AuctionStatusID 
            FROM Auction.AuctionStatus 
            WHERE StatusDescription = 'ONGOING'
        );

        DECLARE @expiredID INT = 
        (
            SELECT AuctionStatusID 
            FROM Auction.AuctionStatus 
            WHERE StatusDescription = 'EXPIRED'
        );

        -- Begin transaction -- 

        BEGIN TRANSACTION;

        -- Mark all active auctions whose expiration date has passed as expired --

        UPDATE Auction.Auctions
        SET AuctionStatusID = @expiredID,
            IsActive = 0,
            EndDate = ExpireDate
        WHERE AuctionStatusID = @ongoingID
          AND ExpireDate <= GETDATE()
          AND IsActive = 1;

        COMMIT;

        SELECT 'Auction status updated successfully.' AS SuccessMessage;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
GO

---------------------------------------------------------------------------------------------------------------------------

-- 4) uspTryBidProduct Procedure: attempts to place a bid for a product on behalf of a customer --

CREATE OR ALTER PROCEDURE Auction.uspTryBidProduct
    @ProductID INT,
    @CustomerID INT,  
    @BidAmount MONEY = NULL
AS
BEGIN
    SET NOCOUNT ON;  

    BEGIN TRY
        -- Declare Variables used to validate the bid and update the auction --

        DECLARE @AuctionID INT;
        DECLARE @AuctionStatusID INT;
        DECLARE @StartDate DATETIME;
        DECLARE @ExpireDate DATETIME;
        DECLARE @InitialBidPrice MONEY;
        DECLARE @CurrentBidPrice MONEY;
        DECLARE @ListPrice MONEY;
        DECLARE @MinBidIncrement DECIMAL(10,2);
        DECLARE @MaxPriceMultiplier DECIMAL(10,2);

        -- Check whether the customer exists before allowing a bid --

        IF NOT EXISTS 
        (
            SELECT 1 
            FROM Sales.Customer AS s
            WHERE s.CustomerID = @CustomerID
        )
        BEGIN                                                                              
            ;THROW 50011, 'Customer does not exist.', 1;         
        END

        -- Retrieve the SOLD status identifier --

        DECLARE @soldID INT = 
        (
            SELECT AuctionStatusID 
            FROM Auction.AuctionStatus 
            WHERE StatusDescription = 'SOLD'
        );

        -- Begin transaction -- 

        BEGIN TRANSACTION;

        -- Lock the active auction row while validating and placing the bid to avoid race conditions under concurrent workload --

        SELECT
            @AuctionID = a.AuctionID,
            @StartDate = a.StartDate,
            @ExpireDate = a.ExpireDate,
            @InitialBidPrice = a.InitialBidPrice,
            @CurrentBidPrice = a.CurrentBidPrice,
            @ListPrice = p.ListPrice
        FROM Auction.Auctions AS a WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN Production.Product AS p
            ON a.ProductID = p.ProductID
        WHERE a.ProductID = @ProductID AND a.IsActive = 1;

        -- Retrieve the MinBidIncrement configured value --

        SELECT @MinBidIncrement = ParameterValue
        FROM Auction.Configuration
        WHERE ParameterName = 'MinBidIncrement' AND Active = 1;

        -- If no active configuration row exists, use the 0.05 as the default value --

        SET @MinBidIncrement = ISNULL(@MinBidIncrement, 0.05);

        -- Retrieve the MaxPriceMultiplier configured value --

        SELECT @MaxPriceMultiplier = ParameterValue
        FROM Auction.Configuration
        WHERE ParameterName = 'MaxPriceMultiplier' AND Active = 1;

        -- If no active row exists, use 1 as the default value --

        SET @MaxPriceMultiplier = ISNULL(@MaxPriceMultiplier, 1);

        -- Confirm that the product still has an active auction after retrieving the auction data --

        IF NOT EXISTS 
        (
            SELECT 1
            FROM Auction.Auctions
            WHERE ProductID = @ProductID AND IsActive = 1
        )
        BEGIN
            ;THROW 50012, 'Product is not currently listed for auction.', 1;
        END

        -- Prevent bids before the auction start date --

        IF GETDATE() < @StartDate
        BEGIN
            ;THROW 50013, 'Auction has not started yet.', 1;
        END

        -- Even if the status update procedure has not been executed yet, prevent bids on auctions that have already expired --

        IF GETDATE() >= @ExpireDate
        BEGIN
            ;THROW 50014, 'Auction has already expired.', 1;
        END

        -- If no bid amount is provided, use the initial bid price for the first bid or increase the current bid by the minimum increment --

        IF @BidAmount IS NULL
        BEGIN
            IF @CurrentBidPrice IS NULL
            BEGIN
                SET @BidAmount = @InitialBidPrice;
            END
            ELSE
            BEGIN
                SET @BidAmount = @CurrentBidPrice + @MinBidIncrement;
            END
        END

        -- Validate the bid amount according to the initial price, current price and configured increment rules --

        IF @CurrentBidPrice IS NULL AND @BidAmount < @InitialBidPrice
        BEGIN
            ;THROW 50015, 'Bid amount cannot be lower than the initial bid price.', 1;
        END

        IF @CurrentBidPrice IS NOT NULL AND @BidAmount < (@CurrentBidPrice + @MinBidIncrement)
        BEGIN
            ;THROW 50016, 'Bid amount does not meet the minimum increment required.', 1;
        END

        IF @BidAmount > @ListPrice * @MaxPriceMultiplier
        BEGIN
            ;THROW 50017, 'Bid amount must not exceed the configured maximum allowed bid price.', 1;
        END

        -- Store the accepted bid in the Bids history table --

        INSERT INTO Auction.Bids (CustomerID, AuctionID, BidAmount, BidDate)
        VALUES (@CustomerID, @AuctionID, @BidAmount, GETDATE());

        -- Update the auction with the latest accepted bid amount --

        UPDATE Auction.Auctions
        SET CurrentBidPrice = @BidAmount
        WHERE AuctionID = @AuctionID;

        -- If the bid reaches the maximum allowed price, or no further valid increment is possible, mark the auction as SOLD --

        IF @BidAmount = @ListPrice * @MaxPriceMultiplier
            OR @BidAmount + @MinBidIncrement > @ListPrice * @MaxPriceMultiplier
        BEGIN
            UPDATE Auction.Auctions
            SET AuctionStatusID = @soldID,
                IsActive = 0,
                EndDate = GETDATE()
            WHERE AuctionID = @AuctionID;
        END

        COMMIT;

        SELECT 'Bid placed successfully.' AS SuccessMessage;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
GO

---------------------------------------------------------------------------------------------------------------------------

-- 5) uspListBidsOffersHistory Procedure: Lists a customer's bid history for a given time interval --

CREATE OR ALTER PROCEDURE Auction.uspListBidsOffersHistory
    @CustomerID INT, 
    @StartTime DATETIME,
    @EndTime DATETIME,
    @Active BIT = 1
AS
BEGIN
    SET NOCOUNT ON;  

    -- Check whether the customer exists before returning bid history --

    IF NOT EXISTS 
    (
        SELECT 1
        FROM Sales.Customer AS s
        WHERE s.CustomerID = @CustomerID
    )
    BEGIN
        ;THROW 50018, 'Customer does not exist.', 1;
    END

    -- Validate date interval provided by the user -- 

    IF @StartTime IS NULL OR @EndTime IS NULL
    BEGIN
        ;THROW 50019, 'Both StartTime and EndTime must be provided.', 1;
    END

    IF @EndTime < @StartTime
    BEGIN
        ;THROW 50020, 'EndTime must be greater than or equal to StartTime.', 1;
    END

    -- Return the customer's bid history, including product information and auction status --

    SELECT
        b.BidID,
        b.CustomerID,
        b.AuctionID,
        a.ProductID,
        p.Name AS ProductName,
        b.BidAmount,
        b.BidDate,
        st.StatusDescription AS AuctionStatus,
        a.IsActive AS IsAuctionActive,
        a.StartDate AS ProductAuctionStartDate,
        a.ExpireDate AS ProductAuctionExpireDate,
        a.EndDate AS ProductAuctionEndDate,
        a.InitialBidPrice,
        a.CurrentBidPrice
    FROM Auction.Bids AS b
    INNER JOIN Auction.Auctions AS a
        ON b.AuctionID = a.AuctionID
    INNER JOIN Production.Product AS p
        ON a.ProductID = p.ProductID
    INNER JOIN Auction.AuctionStatus AS st
        ON a.AuctionStatusID = st.AuctionStatusID
    WHERE b.CustomerID = @CustomerID
      AND b.BidDate BETWEEN @StartTime AND @EndTime
      AND (@Active = 0 OR a.IsActive = 1)
    ORDER BY b.BidDate DESC;
END;
GO

---------------------------------------------------------------------------------------------------------------------------
