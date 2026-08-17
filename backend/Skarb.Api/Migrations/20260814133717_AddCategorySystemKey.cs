using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Skarb.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddCategorySystemKey : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "SystemKey",
                table: "Categories",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SystemKey",
                table: "Categories");
        }
    }
}
