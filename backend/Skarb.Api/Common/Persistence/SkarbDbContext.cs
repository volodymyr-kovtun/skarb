using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Domain;

namespace Skarb.Api.Common.Persistence;

public class SkarbDbContext(DbContextOptions<SkarbDbContext> options) : DbContext(options)
{
    public DbSet<Account> Accounts => Set<Account>();
    public DbSet<Transaction> Transactions => Set<Transaction>();
    public DbSet<Category> Categories => Set<Category>();
    public DbSet<Tag> Tags => Set<Tag>();
    public DbSet<BankConnection> Connections => Set<BankConnection>();
    public DbSet<CategoryRule> CategoryRules => Set<CategoryRule>();
    public DbSet<SyncLog> SyncLogs => Set<SyncLog>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Transaction>()
            .HasIndex(t => new { t.AccountId, t.ExternalId })
            .IsUnique()
            .HasFilter("\"ExternalId\" IS NOT NULL");
        b.Entity<Transaction>().HasIndex(t => t.OccurredAt);
        b.Entity<Transaction>().HasIndex(t => t.TransferGroupId);
        b.Entity<Transaction>()
            .HasOne(t => t.Account)
            .WithMany(a => a.Transactions)
            .OnDelete(DeleteBehavior.Cascade);
        b.Entity<Transaction>()
            .HasOne(t => t.Category)
            .WithMany(c => c.Transactions)
            .OnDelete(DeleteBehavior.SetNull);
        b.Entity<Transaction>()
            .HasMany(t => t.Tags)
            .WithMany(t => t.Transactions);
        b.Entity<Transaction>().Property(t => t.Amount).HasPrecision(18, 2);

        b.Entity<Account>()
            .HasOne(a => a.Connection)
            .WithMany(c => c.Accounts)
            .OnDelete(DeleteBehavior.SetNull);
        b.Entity<Account>().Property(a => a.Balance).HasPrecision(18, 2);
        b.Entity<Account>().Property(a => a.CreditLimit).HasPrecision(18, 2);

        b.Entity<Category>().HasIndex(c => c.Name).IsUnique();
        b.Entity<CategoryRule>()
            .HasOne(r => r.Category)
            .WithMany(c => c.Rules)
            .OnDelete(DeleteBehavior.Cascade);
        b.Entity<Tag>().HasIndex(t => t.Name).IsUnique();
    }
}
