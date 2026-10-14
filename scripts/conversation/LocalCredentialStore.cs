using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace GdPal.Conversation;

/// <summary>Credentials in private app data. The random key stays on this device;
/// this is local file protection, not a hardware-backed keystore.</summary>
public sealed class LocalCredentialStore(string directory) : IChatCredentialStore
{
    private readonly object _gate = new();
    private string PathFor(string endpoint) => LocalFiles.Within(directory, LocalFiles.Hash(endpoint) + ".bin");

    public string Read(string endpoint)
    {
        lock (_gate)
        {
            string path = PathFor(endpoint);
            if (!File.Exists(path)) return "";
            if (new FileInfo(path).Length is < 29 or > 8192) throw new InvalidDataException("本地凭据格式无效。");
            byte[] bytes = File.ReadAllBytes(path), key = DeviceKey(false), plain = new byte[bytes.Length - 29];
            try
            {
                if (bytes[0] != 1) throw new InvalidDataException("本地凭据格式无效。");
                using var cipher = new AesGcm(key, 16);
                cipher.Decrypt(bytes.AsSpan(1, 12), bytes.AsSpan(29), bytes.AsSpan(13, 16), plain, Encoding.UTF8.GetBytes(endpoint));
                return Encoding.UTF8.GetString(plain);
            }
            finally { CryptographicOperations.ZeroMemory(key); CryptographicOperations.ZeroMemory(plain); }
        }
    }

    public void Write(string endpoint, string value)
    {
        lock (_gate)
        {
            if (value.Length == 0) { Delete(endpoint); return; }
            byte[] plain = Encoding.UTF8.GetBytes(value);
            if (plain.Length > 5120) throw new ArgumentException("Key 过长。");
            byte[] key = DeviceKey(true), bytes = new byte[29 + plain.Length];
            try
            {
                bytes[0] = 1;
                RandomNumberGenerator.Fill(bytes.AsSpan(1, 12));
                using var cipher = new AesGcm(key, 16);
                cipher.Encrypt(bytes.AsSpan(1, 12), plain, bytes.AsSpan(29), bytes.AsSpan(13, 16), Encoding.UTF8.GetBytes(endpoint));
                string path = PathFor(endpoint), temporary = path + "." + Guid.NewGuid().ToString("N") + ".writing";
                try { WritePrivate(temporary, bytes); File.Move(temporary, path, true); }
                finally { if (File.Exists(temporary)) LocalFiles.DeleteOrStage(temporary, directory); }
            }
            finally { CryptographicOperations.ZeroMemory(key); CryptographicOperations.ZeroMemory(plain); }
        }
    }

    public void Delete(string endpoint)
    {
        lock (_gate) LocalFiles.DeleteOrStage(PathFor(endpoint), directory);
    }

    private byte[] DeviceKey(bool create)
    {
        string path = LocalFiles.Within(directory, "device-key.bin");
        if (!File.Exists(path) && create)
        {
            Directory.CreateDirectory(directory);
            if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(directory, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            byte[] generated = RandomNumberGenerator.GetBytes(32);
            string temporary = path + "." + Guid.NewGuid().ToString("N") + ".writing";
            try
            {
                WritePrivate(temporary, generated);
                try { File.Move(temporary, path); }
                catch (IOException) when (File.Exists(path)) { } // Another instance created the device key first.
            }
            finally
            {
                CryptographicOperations.ZeroMemory(generated);
                if (File.Exists(temporary)) LocalFiles.DeleteOrStage(temporary, directory);
            }
        }
        if (!File.Exists(path) || new FileInfo(path).Length != 32) throw new InvalidDataException("本地凭据无法解锁，请重新输入 Key。");
        return File.ReadAllBytes(path);
    }

    private static void WritePrivate(string path, byte[] bytes)
    {
        var options = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.None };
        if (!OperatingSystem.IsWindows()) options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
        using var file = new FileStream(path, options);
        file.Write(bytes); file.Flush(true);
    }
}
