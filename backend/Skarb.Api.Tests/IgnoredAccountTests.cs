using Skarb.Api.Common.Domain;

namespace Skarb.Api.Tests;

/// <summary>
/// Deleting a synced account has to be remembered on its connection: sync rediscovers every
/// account the bank reports, so without this the deleted one returns on the next round.
/// </summary>
public class IgnoredAccountTests
{
    [Fact]
    public void Ignoring_an_account_records_its_provider_side_id()
    {
        var conn = new BankConnection();
        conn.Ignore("zJLSImF1PS5XwrKqABOP4g");
        Assert.Equal(["zJLSImF1PS5XwrKqABOP4g"], conn.IgnoredExternalIds);
    }

    [Fact]
    public void Ignoring_the_same_account_twice_does_not_duplicate_it()
    {
        var conn = new BankConnection();
        conn.Ignore("abc");
        conn.Ignore("abc");
        Assert.Equal(["abc"], conn.IgnoredExternalIds);
    }

    [Fact]
    public void Each_ignored_account_is_kept_alongside_the_others()
    {
        var conn = new BankConnection();
        conn.Ignore("abc");
        conn.Ignore("def");
        Assert.Equal(["abc", "def"], conn.IgnoredExternalIds);
    }

    [Fact]
    public void Ignoring_assigns_a_new_list_so_the_change_is_tracked()
    {
        // EF compares primitive collections by snapshot; mutating in place can go unsaved.
        var conn = new BankConnection();
        var before = conn.IgnoredExternalIds;
        conn.Ignore("abc");
        Assert.NotSame(before, conn.IgnoredExternalIds);
    }
}
