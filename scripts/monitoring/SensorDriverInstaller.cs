using System;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;

namespace GdPal.Monitoring;

internal static class SensorDriverInstaller
{
    internal const string Version = "2.2.0";
    internal const string Sha256 = "1F519A22E47187F70A1379A48CA604981C4FCF694F4E65B734AAA74A9FBA3032";
    internal const string DownloadUrl = "https://github.com/namazso/PawnIO.Setup/releases/download/2.2.0/PawnIO_setup.exe";
    private static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(60), MaxResponseContentBufferSize = 8 * 1024 * 1024 };

    // Resolve the component on this PC; a copied preference file never proves installation.
    internal static async Task<string> PrepareAsync(string[] bundledPaths, string cachePath, CancellationToken cancellation)
    {
        foreach (string path in bundledPaths)
            if (File.Exists(path)) { await VerifyAsync(path, cancellation); return path; }
        if (File.Exists(cachePath)) { await VerifyAsync(cachePath, cancellation); return cachePath; }
        byte[] bytes = await Client.GetByteArrayAsync(DownloadUrl, cancellation);
        if (Convert.ToHexString(SHA256.HashData(bytes)) != Sha256)
            throw new IOException("官方安装器校验失败，请稍后重试或从官方发行页下载。");
        Directory.CreateDirectory(Path.GetDirectoryName(cachePath)!);
        string temporary = cachePath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            await File.WriteAllBytesAsync(temporary, bytes, cancellation);
            File.Move(temporary, cachePath, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
        return cachePath;
    }

    private static async Task VerifyAsync(string path, CancellationToken cancellation)
    {
        await using var file = File.OpenRead(path);
        if (Convert.ToHexString(await SHA256.HashDataAsync(file, cancellation)) != Sha256)
            throw new IOException("安装器校验失败，请移除损坏的 PawnIO 安装器后重试。");
    }
}
