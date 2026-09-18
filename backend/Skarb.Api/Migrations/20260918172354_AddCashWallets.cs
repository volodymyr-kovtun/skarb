using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Skarb.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddCashWallets : Migration
    {
        // Manual accounts filed under "Cash" are what a wallet was before wallets existed — the
        // account form itself suggested "cash" as the institution. Matching is on that name alone,
        // trimmed and case-blind; anything it misses can be made a wallet from the account editor.
        private const string CashAccounts = """
            "Provider" = 'manual' AND lower(btrim("Bank")) = 'cash'
            """;

        // One keeper per currency: a live account over an archived one, a counted one over one
        // marked "don't count", then the oldest. Deterministic, because the statements below each
        // work it out again and have to agree.
        private const string Ranked = $"""
            SELECT "Id", first_value("Id") OVER (
                       PARTITION BY "Currency" ORDER BY "IsArchived", "IsExcluded", "CreatedAt", "Id") AS "Keeper"
            FROM "Accounts"
            WHERE {CashAccounts}
            """;

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<decimal>(
                name: "CashAmount",
                table: "Transactions",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CashCurrency",
                table: "Transactions",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "IsCash",
                table: "Accounts",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            // Nothing stopped a second cash account in the same currency from being added, and
            // the index below cannot be built while one exists. Each extra account is folded into
            // its keeper — transactions first, as separate statements, so the cascade on the
            // delete that follows has nothing left to take with it. ExternalId is dropped on the
            // way: it is only unique per account, and two folded accounts could carry the same one.
            migrationBuilder.Sql($"""
                UPDATE "Transactions" t
                SET "AccountId" = r."Keeper", "ExternalId" = NULL
                FROM ({Ranked}) r
                WHERE t."AccountId" = r."Id" AND r."Id" <> r."Keeper";
                """);
            migrationBuilder.Sql($"""
                DELETE FROM "Accounts" a
                USING ({Ranked}) r
                WHERE a."Id" = r."Id" AND r."Id" <> r."Keeper";
                """);
            // The name is restated in the one spelling wallets are created with from here on, so
            // " cash" and "CASH" do not live on as separate labels on every transaction row.
            migrationBuilder.Sql($"""
                UPDATE "Accounts" SET "IsCash" = TRUE, "Bank" = 'Cash' WHERE {CashAccounts};
                """);
            // A manual account's balance is the sum of its rows, and a keeper just gained some.
            migrationBuilder.Sql("""
                UPDATE "Accounts" a
                SET "Balance" = COALESCE((SELECT SUM(t."Amount") FROM "Transactions" t WHERE t."AccountId" = a."Id"), 0)
                WHERE a."IsCash";
                """);

            migrationBuilder.CreateIndex(
                name: "IX_Accounts_Currency",
                table: "Accounts",
                column: "Currency",
                unique: true,
                filter: "\"IsCash\"");
        }

        /// <inheritdoc />
        /// <remarks>Drops the schema only. Accounts folded together on the way up stay folded.</remarks>
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Accounts_Currency",
                table: "Accounts");

            migrationBuilder.DropColumn(
                name: "CashAmount",
                table: "Transactions");

            migrationBuilder.DropColumn(
                name: "CashCurrency",
                table: "Transactions");

            migrationBuilder.DropColumn(
                name: "IsCash",
                table: "Accounts");
        }
    }
}
