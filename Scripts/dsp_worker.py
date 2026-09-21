import hashlib
import json
import sys
import numpy as np
import soundfile as sf

def generate_pcm_fingerprint(wav_path):
    try:
        # Read raw PCM samples and audio properties
        data, sr = sf.read(wav_path, dtype='float32')
        
        # Ensure consistent memory layout (C-contiguous)
        pcm_bytes = np.ascontiguousarray(data).tobytes()
        
        # Compute standard cryptographic hashes on audio data alone
        sha256_hash = hashlib.sha256(pcm_bytes).hexdigest()
        md5_hash = hashlib.md5(pcm_bytes).hexdigest()
        
        duration_sec = len(data) / sr
        
        return {
            "status": "success",
            "file": wav_path,
            "sample_rate": sr,
            "channels": data.shape[1] if data.ndim > 1 else 1,
            "duration": round(duration_sec, 3),
            "pcm_sha256": sha256_hash,
            "pcm_md5": md5_hash
        }
    except Exception as e:
        return {"status": "error", "message": str(e)}

if __name__ == "__main__":
    if len(sys.argv) > 1:
        result = generate_pcm_fingerprint(sys.argv[1])
        print(json.dumps(result))