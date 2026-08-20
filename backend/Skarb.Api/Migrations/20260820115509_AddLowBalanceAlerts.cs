using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Skarb.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddLowBalanceAlerts : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "LowBalanceChatId",
                table: "Accounts",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "LowBalanceNotifiedAt",
                table: "Accounts",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "LowBalanceThreshold",
                table: "Accounts",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "NotificationSettings",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TelegramBotToken = table.Column<string>(type: "text", nullable: false),
                    TelegramBotUsername = table.Column<string>(type: "text", nullable: true),
                    TelegramChatId = table.Column<string>(type: "text", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NotificationSettings", x => x.Id);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "NotificationSettings");

            migrationBuilder.DropColumn(
                name: "LowBalanceChatId",
                table: "Accounts");

            migrationBuilder.DropColumn(
                name: "LowBalanceNotifiedAt",
                table: "Accounts");

            migrationBuilder.DropColumn(
                name: "LowBalanceThreshold",
                table: "Accounts");
        }
    }
}
