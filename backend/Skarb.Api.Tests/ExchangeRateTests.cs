using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Infrastructure.Fx;

namespace Skarb.Api.Tests;

/// <summary>
/// Conversion behaviour on the offline fallback rates — the rate provider is unreachable
/// here, which is exactly the path a laptop without network takes.
/// </summary>
public class ExchangeRateTests
{
    // Fallback table: 1 PLN = 0.234 EUR = 0.274 USD.
    private static OpenErApiExchangeRateService Service(string baseCurrency = "PLN") =>
        new(new OfflineHttpClientFactory(),
            Options.Create(new FxOptions { BaseCurrency = baseCurrency }),
            NullLogger<OpenErApiExchangeRateService>.Instance);

    [Fact]
    public async Task Same_currency_is_returned_untouched()
    {
        Assert.Equal(123.45m, await Service().ConvertAsync(123.45m, "EUR", "EUR"));
        Assert.Equal(123.45m, await Service().ConvertAsync(123.45m, "eur", "EUR"));
    }

    [Fact]
    public async Task Converts_from_and_to_the_base_currency()
    {
        var fx = Service();
        Assert.Equal(23.40m, await fx.ConvertAsync(100m, "PLN", "EUR"));
        Assert.Equal(427.35m, await fx.ConvertAsync(100m, "EUR", "PLN"));
    }

    [Fact]
    public async Task Converts_between_two_non_base_currencies_through_the_base()
    {
        // 100 EUR -> 427.35 PLN -> 117.09 USD
        Assert.Equal(117.09m, await Service().ConvertAsync(100m, "EUR", "USD"));
    }

    [Fact]
    public async Task Unknown_currency_is_reported_and_left_unconverted()
    {
        var fx = Service();
        Assert.False(await fx.IsKnownAsync("XYZ"));
        Assert.True(await fx.IsKnownAsync("eur"));
        Assert.Equal(100m, await fx.ConvertAsync(100m, "XYZ", "EUR"));
    }

    [Fact]
    public async Task Base_currency_is_always_known_even_when_the_rate_table_omits_it()
    {
        var fx = Service("EUR"); // fallback table is PLN-centric and has no EUR->EUR entry
        Assert.True(await fx.IsKnownAsync("EUR"));
        Assert.Equal(50m, await fx.ConvertAsync(50m, "EUR", "EUR"));
    }

    /// <summary>Every request fails, so the service falls back to its built-in rates.</summary>
    private sealed class OfflineHttpClientFactory : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(new FailingHandler());

        private sealed class FailingHandler : HttpMessageHandler
        {
            protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) =>
                throw new HttpRequestException("offline");
        }
    }
}
