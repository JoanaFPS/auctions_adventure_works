# Adventure Works Auctions

This project extends the AdventureWorks database with an `Auction` schema to support an online stock clearance auction campaign. The solution is implemented in T-SQL through an idempotent script that creates the required tables, configuration settings, indexes, and stored procedures for adding products to auctions, placing bids, removing auctioned products, updating auction status, and viewing customer bid history. The project focuses on database design, data integrity, error handling, and supporting high workload scenarios during the campaign period.

This project uses the AdventureWorks sample database.

https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure
