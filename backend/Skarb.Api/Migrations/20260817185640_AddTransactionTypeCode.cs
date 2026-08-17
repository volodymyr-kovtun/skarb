using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Skarb.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddTransactionTypeCode : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "TypeCode",
                table: "Transactions",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "TypeCode",
                table: "Transactions");
        }
    }
}
