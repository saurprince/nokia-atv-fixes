package local.avlfix;

import android.util.Base64;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.Closeable;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.math.BigInteger;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.interfaces.RSAPublicKey;

/**
 * Minimal client for the classic ADB protocol (the one `adb connect host:5555` speaks), used to run
 * one shell command on this same TV. The first connection with a new key makes the TV show
 * "Allow USB debugging?"; once the owner ticks "Always allow", later connections are silent.
 */
final class AdbClient implements Closeable {
    private static final int A_CNXN = 0x4e584e43;
    private static final int A_AUTH = 0x48545541;
    private static final int A_OPEN = 0x4e45504f;
    private static final int A_OKAY = 0x59414b4f;
    private static final int A_CLSE = 0x45534c43;
    private static final int A_WRTE = 0x45545257;
    private static final int AUTH_TOKEN = 1;
    private static final int AUTH_SIGNATURE = 2;
    private static final int AUTH_RSAPUBLICKEY = 3;
    private static final int VERSION = 0x01000000;
    private static final int MAX_DATA = 256 * 1024;
    /** ASN.1 DigestInfo prefix for SHA-1: adbd treats the 20-byte token as a SHA-1 digest. */
    private static final byte[] SHA1_DIGEST_INFO = {
            0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14};

    private final Socket socket;
    private final DataInputStream in;
    private final OutputStream out;

    private static final class Message {
        int command;
        int arg0;
        int arg1;
        byte[] data;
    }

    AdbClient(String host, int port) throws IOException {
        socket = new Socket();
        socket.connect(new InetSocketAddress(host, port), 5000);
        socket.setSoTimeout(15000);
        in = new DataInputStream(new BufferedInputStream(socket.getInputStream()));
        out = socket.getOutputStream();
    }

    /**
     * Connects and authenticates. If the TV does not know the key yet it shows the "Allow USB
     * debugging?" prompt; this waits up to promptWaitMs for the owner to accept it.
     */
    void connect(KeyPair key, String keyName, int promptWaitMs, AvlLog log) throws Exception {
        send(A_CNXN, VERSION, MAX_DATA, "host::\0".getBytes(StandardCharsets.US_ASCII));
        boolean signed = false;
        boolean offeredKey = false;
        while (true) {
            Message m = read();
            if (m.command == A_CNXN) {
                return;
            }
            if (m.command != A_AUTH || m.arg0 != AUTH_TOKEN) {
                throw new IOException("unexpected ADB message 0x" + Integer.toHexString(m.command));
            }
            if (!signed) {
                send(A_AUTH, AUTH_SIGNATURE, 0, sign(key.getPrivate(), m.data));
                signed = true;
            } else if (!offeredKey) {
                log.write("TV does not know this app's key yet - asking it to allow debugging (accept on screen)");
                String pub = adbPublicKey((RSAPublicKey) key.getPublic()) + " " + keyName + "\0";
                send(A_AUTH, AUTH_RSAPUBLICKEY, 0, pub.getBytes(StandardCharsets.US_ASCII));
                offeredKey = true;
                socket.setSoTimeout(promptWaitMs);
            } else {
                throw new IOException("the TV rejected this app's debugging key");
            }
        }
    }

    /** Runs a shell command and returns its output (waits up to timeoutMs between output chunks). */
    String shell(String command, int timeoutMs) throws IOException {
        socket.setSoTimeout(timeoutMs);
        final int localId = 1;
        send(A_OPEN, localId, 0, ("shell:" + command + "\0").getBytes(StandardCharsets.UTF_8));
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        while (true) {
            Message m = read();
            if (m.command == A_WRTE) {
                output.write(m.data);
                send(A_OKAY, localId, m.arg0, null);
            } else if (m.command == A_CLSE) {
                send(A_CLSE, localId, m.arg0, null);
                return new String(output.toByteArray(), StandardCharsets.UTF_8);
            }
            // A_OKAY just acknowledges the stream; nothing to do.
        }
    }

    @Override
    public void close() throws IOException {
        socket.close();
    }

    private void send(int command, int arg0, int arg1, byte[] data) throws IOException {
        if (data == null) {
            data = new byte[0];
        }
        int checksum = 0;
        for (byte b : data) {
            checksum += b & 0xff;
        }
        ByteBuffer buf = ByteBuffer.allocate(24 + data.length).order(ByteOrder.LITTLE_ENDIAN);
        buf.putInt(command).putInt(arg0).putInt(arg1).putInt(data.length).putInt(checksum).putInt(~command).put(data);
        out.write(buf.array());
        out.flush();
    }

    private Message read() throws IOException {
        byte[] header = new byte[24];
        in.readFully(header);
        ByteBuffer buf = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN);
        Message m = new Message();
        m.command = buf.getInt();
        m.arg0 = buf.getInt();
        m.arg1 = buf.getInt();
        int length = buf.getInt();
        if (length < 0 || length > 1024 * 1024) {
            throw new IOException("bad ADB message length " + length);
        }
        m.data = new byte[length];
        in.readFully(m.data);
        return m;
    }

    /** RSA PKCS#1 v1.5 signature of the token as a SHA-1 digest (what adbd verifies). */
    private static byte[] sign(PrivateKey key, byte[] token) throws Exception {
        Signature s = Signature.getInstance("NONEwithRSA");
        s.initSign(key);
        s.update(SHA1_DIGEST_INFO);
        s.update(token);
        return s.sign();
    }

    /** Public key in adbd's format: base64 of Android's RSAPublicKey struct (2048-bit). */
    private static String adbPublicKey(RSAPublicKey pub) {
        final int words = 64;
        BigInteger n = pub.getModulus();
        BigInteger r32 = BigInteger.ONE.shiftLeft(32);
        BigInteger n0inv = r32.subtract(n.mod(r32).modInverse(r32));           // -1 / n[0] mod 2^32
        BigInteger rr = BigInteger.ONE.shiftLeft(words * 32 * 2).mod(n);       // R^2 mod n, R = 2^2048
        ByteBuffer buf = ByteBuffer.allocate(4 + 4 + words * 4 * 2 + 4).order(ByteOrder.LITTLE_ENDIAN);
        buf.putInt(words);
        buf.putInt(n0inv.intValue());
        for (int i = 0; i < words; i++) {
            buf.putInt(n.shiftRight(i * 32).intValue());
        }
        for (int i = 0; i < words; i++) {
            buf.putInt(rr.shiftRight(i * 32).intValue());
        }
        buf.putInt(pub.getPublicExponent().intValue());
        return Base64.encodeToString(buf.array(), Base64.NO_WRAP);
    }
}
