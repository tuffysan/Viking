using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.DataProtection;

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls("http://0.0.0.0:8080");

var dataDir = Environment.GetEnvironmentVariable("VIKING_DATA_DIR") ?? "/var/lib/viking-iptv";
Directory.CreateDirectory(dataDir);
Directory.CreateDirectory(Path.Combine(dataDir, "keys"));
builder.Services.AddDataProtection().PersistKeysToFileSystem(new DirectoryInfo(Path.Combine(dataDir, "keys"))).SetApplicationName("VikingIPTV");
builder.Services.AddSingleton(new Store(Path.Combine(dataDir, "data.json")));
builder.Services.AddHttpClient("provider", c => {
    c.Timeout = TimeSpan.FromSeconds(15);
    c.DefaultRequestHeaders.UserAgent.ParseAdd("Viking-IPTV-LXC/1.1 (+local subscription manager)");
});

var app = builder.Build();
app.UseDefaultFiles();
app.UseStaticFiles();

var protector = app.Services.GetRequiredService<IDataProtectionProvider>().CreateProtector("VikingIPTV.AccountSecrets.v1");

app.MapGet("/api/health", () => Results.Ok(new { status = "ok", app = "Viking IPTV", version = "1.7.6", hostname = Environment.MachineName, time = DateTimeOffset.UtcNow }));

app.MapGet("/api/provider", () => Results.Ok(ProviderCatalog.Info));
app.MapGet("/api/packages", () => Results.Ok(ProviderCatalog.Packages));

app.MapGet("/api/provider/live", async (IHttpClientFactory factory) => {
    var client = factory.CreateClient("provider");
    var results = new List<object>();
    foreach (var p in ProviderCatalog.Packages.Where(x => x.Months is 1 or 3 or 6 or 12 or 24 && x.Connections == 1)) {
        var url = p.RenewUrl;
        try
        {
            var html = await client.GetStringAsync(url);
            var match = Regex.Match(html, @"(?is)(\d[\d\s]{1,5})\s*kr");
            var text = Regex.Replace(match.Success ? match.Groups[1].Value : "", @"\s+", "");
            results.Add(new { p.Id, p.Name, url, reachable = true, detectedPrice = int.TryParse(text, out var amount) ? amount : (int?)null });
        }
        catch (Exception ex)
        {
            results.Add(new { p.Id, p.Name, url, reachable = false, error = ex.Message });
        }
    }
    return Results.Ok(new { checkedAt = DateTimeOffset.UtcNow, results });
});

app.MapGet("/api/settings", (Store store) => Results.Ok(store.Read().Settings.Public()));
app.MapPut("/api/settings", (SettingsInput input, Store store) => {
    if (input.ServiceFeeSek < 1) return Results.BadRequest(new { error = "Serviceavgiften måste vara minst 1 kr." });
    if (string.IsNullOrWhiteSpace(input.SwishNumber)) return Results.BadRequest(new { error = "Swish-nummer måste anges." });
    AppSettings? updated = null;
    store.Update(d => {
        d.Settings.ServiceFeeSek = input.ServiceFeeSek;
        d.Settings.SwishNumber = input.SwishNumber.Trim();
        d.Settings.SwishRecipientName = input.SwishRecipientName?.Trim() ?? "";
        d.Settings.SwishMessagePrefix = string.IsNullOrWhiteSpace(input.SwishMessagePrefix) ? "VIKING" : input.SwishMessagePrefix.Trim();
        d.Settings.UpdatedAt = DateTimeOffset.UtcNow;
        updated = d.Settings;
    });
    return Results.Ok(updated!.Public());
});

app.MapGet("/api/accounts", (Store store) => Results.Ok(store.Read().Accounts.Select(a => a.Public())));
app.MapGet("/api/accounts/{id:guid}", (Guid id, Store store) => {
    var a = store.Read().Accounts.FirstOrDefault(x => x.Id == id);
    return a is null ? Results.NotFound() : Results.Ok(a.Public(includeSecrets: false));
});

app.MapPost("/api/accounts", (AccountInput input, Store store) => {
    var account = new Account {
        Id = Guid.NewGuid(), Name = input.Name.Trim(), FirstName = input.FirstName.Trim(), LastName = input.LastName.Trim(),
        Email = input.Email.Trim(), Phone = input.Phone.Trim(), PortalUrl = input.PortalUrl.Trim(), MacAddress = input.MacAddress.Trim(),
        UsernameProtected = string.IsNullOrWhiteSpace(input.Username) ? "" : protector.Protect(input.Username.Trim()),
        PasswordProtected = string.IsNullOrWhiteSpace(input.Password) ? "" : protector.Protect(input.Password),
        ExpiresOn = input.ExpiresOn, Notes = input.Notes.Trim(), CreatedAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow
    };
    store.Update(d => d.Accounts.Add(account));
    return Results.Created($"/api/accounts/{account.Id}", account.Public());
});

app.MapPut("/api/accounts/{id:guid}", (Guid id, AccountInput input, Store store) => {
    Account? updated = null;
    store.Update(d => {
        var a = d.Accounts.FirstOrDefault(x => x.Id == id); if (a is null) return;
        a.Name = input.Name.Trim(); a.FirstName = input.FirstName.Trim(); a.LastName = input.LastName.Trim();
        a.Email = input.Email.Trim(); a.Phone = input.Phone.Trim(); a.PortalUrl = input.PortalUrl.Trim(); a.MacAddress = input.MacAddress.Trim();
        if (!string.IsNullOrWhiteSpace(input.Username)) a.UsernameProtected = protector.Protect(input.Username.Trim());
        if (!string.IsNullOrWhiteSpace(input.Password)) a.PasswordProtected = protector.Protect(input.Password);
        a.ExpiresOn = input.ExpiresOn; a.Notes = input.Notes.Trim(); a.UpdatedAt = DateTimeOffset.UtcNow; updated = a;
    });
    return updated is null ? Results.NotFound() : Results.Ok(updated.Public());
});

app.MapDelete("/api/accounts/{id:guid}", (Guid id, Store store) => {
    var removed = false; store.Update(d => { var a = d.Accounts.FirstOrDefault(x => x.Id == id); if (a != null) removed = d.Accounts.Remove(a); });
    return removed ? Results.NoContent() : Results.NotFound();
});

app.MapGet("/api/accounts/{id:guid}/credentials", (Guid id, Store store) => {
    var a = store.Read().Accounts.FirstOrDefault(x => x.Id == id); if (a is null) return Results.NotFound();
    string Unprotect(string value) { try { return string.IsNullOrEmpty(value) ? "" : protector.Unprotect(value); } catch { return ""; } }
    return Results.Ok(new { username = Unprotect(a.UsernameProtected), password = Unprotect(a.PasswordProtected), portalUrl = a.PortalUrl, macAddress = a.MacAddress });
});

app.MapGet("/api/orders", (Store store) => Results.Ok(store.Read().Orders.OrderByDescending(x => x.CreatedAt)));
app.MapPost("/api/orders", (OrderInput input, Store store) => {
    var pkg = ProviderCatalog.Packages.FirstOrDefault(p => p.Id == input.PackageId);
    if (pkg is null) return Results.BadRequest(new { error = "Okänt paket." });
    if (input.Type == "renew" && input.AccountId is null) return Results.BadRequest(new { error = "Välj konto vid förlängning." });
    var settings = store.Read().Settings;
    if (settings.ServiceFeeSek < 1 || string.IsNullOrWhiteSpace(settings.SwishNumber))
        return Results.BadRequest(new { error = "Serviceavgift och mottagande Swish-nummer måste konfigureras under Inställningar innan en beställning kan skapas." });
    var orderId = Guid.NewGuid();
    var reference = $"{settings.SwishMessagePrefix}-{orderId.ToString("N")[..8].ToUpperInvariant()}";
    var order = new Order {
        Id = orderId, Type = input.Type == "renew" ? "renew" : "new", AccountId = input.AccountId,
        PackageId = pkg.Id, PackageName = pkg.Name, PriceSek = pkg.PriceSek, Status = "prepared", PaymentMethod = input.PaymentMethod,
        CheckoutUrl = input.Type == "renew" ? pkg.RenewUrl : pkg.BuyUrl, Notes = input.Notes?.Trim() ?? "", CreatedAt = DateTimeOffset.UtcNow,
        SafelloTotalSek = input.PaymentMethod == "safello-swish" ? (int)Math.Ceiling(pkg.PriceSek * 1.10m) : null,
        ServiceFeeSek = settings.ServiceFeeSek, ServiceFeeSwishNumber = settings.SwishNumber, ServiceFeeRecipientName = settings.SwishRecipientName,
        ServiceFeeReference = reference, ServiceFeeStatus = "unpaid"
    };
    store.Update(d => d.Orders.Add(order));
    return Results.Ok(order);
});

app.MapPatch("/api/orders/{id:guid}/status/{status}", (Guid id, string status, Store store) => {
    var allowed = new[] { "prepared", "submitted", "payment-pending", "paid", "activated", "cancelled" };
    if (!allowed.Contains(status)) return Results.BadRequest(new { error = "Ogiltig status." });
    Order? found = null; store.Update(d => { found = d.Orders.FirstOrDefault(x => x.Id == id); if (found != null) { found.Status = status; found.UpdatedAt = DateTimeOffset.UtcNow; } });
    return found is null ? Results.NotFound() : Results.Ok(found);
});

app.MapPatch("/api/orders/{id:guid}/service-fee/{status}", (Guid id, string status, Store store) => {
    var allowed = new[] { "unpaid", "paid" };
    if (!allowed.Contains(status)) return Results.BadRequest(new { error = "Ogiltig status för serviceavgift." });
    Order? found = null; store.Update(d => { found = d.Orders.FirstOrDefault(x => x.Id == id); if (found != null) { found.ServiceFeeStatus = status; found.UpdatedAt = DateTimeOffset.UtcNow; } });
    return found is null ? Results.NotFound() : Results.Ok(found);
});

app.MapGet("/api/payment/safello/{packageId}", (string packageId) => {
    var pkg = ProviderCatalog.Packages.FirstOrDefault(x => x.Id == packageId); if (pkg is null) return Results.NotFound();
    var fee = (int)Math.Ceiling(pkg.PriceSek * 0.10m); var total = pkg.PriceSek + fee;
    return Results.Ok(new {
        package = pkg.Name, packagePriceSek = pkg.PriceSek, feePercent = 10, feeSek = fee, totalSek = total,
        vikingInstructions = ProviderCatalog.Info.SafelloInstructionsUrl,
        safelloUrl = "https://app.safello.com/",
        warning = "Kontrollera alltid aktuellt belopp och mottagaradress på Vikings officiella instruktioner innan betalning. Swish/BankID måste godkännas av dig."
    });
});

app.MapFallbackToFile("index.html");
app.Run();

record AccountInput(string Name = "", string FirstName = "", string LastName = "", string Email = "", string Phone = "", string PortalUrl = "", string Username = "", string Password = "", string MacAddress = "", DateOnly? ExpiresOn = null, string Notes = "");
record OrderInput(string Type, string PackageId, Guid? AccountId, string PaymentMethod = "safello-swish", string? Notes = null);
record SettingsInput(int ServiceFeeSek, string SwishNumber, string? SwishRecipientName = null, string? SwishMessagePrefix = "VIKING");

class AppData { public List<Account> Accounts { get; set; } = []; public List<Order> Orders { get; set; } = []; public AppSettings Settings { get; set; } = new(); }
class AppSettings {
    public int ServiceFeeSek { get; set; } = 0; public string SwishNumber { get; set; } = ""; public string SwishRecipientName { get; set; } = ""; public string SwishMessagePrefix { get; set; } = "VIKING"; public DateTimeOffset? UpdatedAt { get; set; }
    public object Public() => new { ServiceFeeSek, SwishNumber, SwishRecipientName, SwishMessagePrefix, UpdatedAt, configured = ServiceFeeSek > 0 && !string.IsNullOrWhiteSpace(SwishNumber) };
}
class Account {
    public Guid Id { get; set; } public string Name { get; set; } = ""; public string FirstName { get; set; } = ""; public string LastName { get; set; } = "";
    public string Email { get; set; } = ""; public string Phone { get; set; } = ""; public string PortalUrl { get; set; } = "";
    public string UsernameProtected { get; set; } = ""; public string PasswordProtected { get; set; } = ""; public string MacAddress { get; set; } = "";
    public DateOnly? ExpiresOn { get; set; } public string Notes { get; set; } = ""; public DateTimeOffset CreatedAt { get; set; } public DateTimeOffset UpdatedAt { get; set; }
    public object Public(bool includeSecrets = false) => new { Id, Name, FirstName, LastName, Email, Phone, PortalUrl, MacAddress, ExpiresOn, Notes, CreatedAt, UpdatedAt, hasCredentials = !string.IsNullOrEmpty(UsernameProtected) || !string.IsNullOrEmpty(PasswordProtected) };
}
class Order {
    public Guid Id { get; set; } public string Type { get; set; } = "new"; public Guid? AccountId { get; set; } public string PackageId { get; set; } = ""; public string PackageName { get; set; } = "";
    public int PriceSek { get; set; } public int? SafelloTotalSek { get; set; } public string PaymentMethod { get; set; } = ""; public string Status { get; set; } = "";
    public int ServiceFeeSek { get; set; } public string ServiceFeeSwishNumber { get; set; } = ""; public string ServiceFeeRecipientName { get; set; } = ""; public string ServiceFeeReference { get; set; } = ""; public string ServiceFeeStatus { get; set; } = "unpaid";
    public string CheckoutUrl { get; set; } = ""; public string Notes { get; set; } = ""; public DateTimeOffset CreatedAt { get; set; } public DateTimeOffset? UpdatedAt { get; set; }
}
class Store {
    readonly string _path; readonly object _gate = new(); readonly JsonSerializerOptions _json = new() { WriteIndented = true };
    public Store(string path) { _path = path; if (!File.Exists(_path)) Save(new AppData()); }
    public AppData Read() { lock (_gate) { try { return JsonSerializer.Deserialize<AppData>(File.ReadAllText(_path), _json) ?? new(); } catch { return new(); } } }
    public void Update(Action<AppData> action) { lock (_gate) { var d = ReadUnsafe(); action(d); SaveUnsafe(d); } }
    AppData ReadUnsafe() { try { return JsonSerializer.Deserialize<AppData>(File.ReadAllText(_path), _json) ?? new(); } catch { return new(); } }
    void Save(AppData d) { lock (_gate) SaveUnsafe(d); }
    void SaveUnsafe(AppData d) { Directory.CreateDirectory(Path.GetDirectoryName(_path)!); var tmp = _path + ".tmp"; File.WriteAllText(tmp, JsonSerializer.Serialize(d, _json)); File.Move(tmp, _path, true); }
}
record Package(string Id, string Name, int Months, int Connections, int PriceSek, string BuyUrl, string RenewUrl);
static class ProviderCatalog {
    public static readonly dynamic Info = new {
        Name = "Viking IPTV", BaseUrl = "https://vikingsiptv.se/", BuyUrl = "https://vikingsiptv.se/kop/", RenewalUrl = "https://vikingsiptv.se/forlangning/",
        SafelloInstructionsUrl = "https://vikingsiptv.se/instruktioner-for-safello/", SafelloFeePercent = 10,
        Note = "Priser och betalningsinstruktioner kan ändras. Kontrollera alltid leverantörens officiella sida före betalning."
    };
    public static readonly List<Package> Packages = [
        new("1m-1", "1 månad", 1, 1, 249, "https://vikingsiptv.se/kop/", "https://vikingsiptv.se/fornya-paket/fornya-1-manad/"),
        new("3m-1", "3 månader", 3, 1, 499, "https://vikingsiptv.se/kop/", "https://vikingsiptv.se/fornya-paket/fornya-3-manader/"),
        new("6m-1", "6 månader", 6, 1, 799, "https://vikingsiptv.se/kop/", "https://vikingsiptv.se/fornya-paket/fornya-6-manader/"),
        new("12m-1", "12 månader", 12, 1, 999, "https://vikingsiptv.se/kop/", "https://vikingsiptv.se/fornya-paket/fornya-12-manader/"),
        new("12m-2", "12 månader · 2 anslutningar", 12, 2, 1499, "https://vikingsiptv.se/kop/", "https://vikingsiptv.se/fornya-paket/fornya-12-manader-2-anslutning/"),
        new("12m-3", "12 månader · 3 anslutningar", 12, 3, 1999, "https://vikingsiptv.se/kop/", "https://vikingsiptv.se/fornya-paket/fornya-12-manader-3-anslutning/"),
        new("24m-1", "24 månader", 24, 1, 1799, "https://vikingsiptv.se/kop/", "https://vikingsiptv.se/fornya-paket/fornya-24-manader/")
    ];
}
