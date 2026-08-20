using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Skarb.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddTransactionInternalSource : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "InternalSource",
                table: "Transactions",
                type: "text",
                nullable: true);

            // Rows written before this column existed still need attributing, because the
            // detector's repair pass only revisits pairings it made itself. Reference groups
            // are recognisable by the shared bank token on both legs; the remaining groups came
            // from amount pairing. An internal row with no group is either an IBAN match or a
            // manual mark — indistinguishable now, so it counts as manual and nothing touches it.
            migrationBuilder.Sql("""
                UPDATE "Transactions" SET "InternalSource" = 'reference'
                WHERE "IsInternal" AND "TransferGroupId" IN (
                    SELECT "TransferGroupId" FROM "Transactions"
                    WHERE "TransferGroupId" IS NOT NULL
                      AND ("Description" ~* '\yFX[0-9]{6,}\y' OR coalesce("Note", '') ~* '\yFX[0-9]{6,}\y'));

                UPDATE "Transactions" SET "InternalSource" = 'pair'
                WHERE "IsInternal" AND "TransferGroupId" IS NOT NULL AND "InternalSource" IS NULL;

                UPDATE "Transactions" SET "InternalSource" = 'manual'
                WHERE "IsInternal" AND "TransferGroupId" IS NULL;
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "InternalSource",
                table: "Transactions");
        }
    }
}
