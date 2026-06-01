import os
import sys

print("[SparkleOS] Bootstrapping unified memory architecture optimizations...", file=sys.stderr)

try:
    import torch
    import psutil

    # 1. Store a pointer to the original function for fallback stability
    _native_mem_get_info = torch.cuda.mem_get_info

    def sparkle_unified_mem_get_info(device=None):
        """
        Intercepts PyTorch VRAM queries to report the actual physical host memory capacity
        minus a protective buffer for concurrent services running on the DGX Spark fabric.
        """
        # Read headroom buffer from environment (default to 4GB)
        buffer_gb = int(os.environ.get("SPARKLE_MEM_BUFFER_GB", 4))
        buffer_bytes = buffer_gb * 1024 * 1024 * 1024
        
        # Pull real-time available LPDDR5x from the host system
        available_host_ram = psutil.virtual_memory().available
        total_host_ram = psutil.virtual_memory().total
        
        # Guarantee we never calculate a negative memory footprint
        usable_memory = max(0, available_host_ram - buffer_bytes)
        
        return (usable_memory, total_host_ram)

    # 2. Inject the hook at the global driver wrapper level
    torch.cuda.mem_get_info = sparkle_unified_mem_get_info
    print("[SparkleOS] Runtime memory monkey-patch fully engaged.", file=sys.stderr)

except Exception as e:
    print(f"[SparkleOS] Critical Warning: Runtime hook failed to initialize: {e}", file=sys.stderr)

