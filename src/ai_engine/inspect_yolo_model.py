#!/usr/bin/env python3
"""
NovaLunch AI Model Inspector
Dynamically parses PyTorch / YOLO11 / YOLOv8 .pt weight files to extract:
- Trained class names (e.g. {0: 'Buttercream Crackers'})
- Model architecture (yolo11n / yolo8n)
- Number of classes (nc)
- Epochs & training settings
- File size & timestamp
"""

import os
import sys
import json
import zipfile
import pickle
import io

def inspect_pt_file(pt_path="src/assets/models/novalunch_yolo.pt"):
    if not os.path.exists(pt_path) and os.path.exists("novalunch_yolo.pt"):
        pt_path = "novalunch_yolo.pt"
    if not os.path.exists(pt_path):
        return {"error": f"File '{pt_path}' not found."}

    file_size_mb = round(os.path.getsize(pt_path) / (1024 * 1024), 2)
    mod_time = os.path.getmtime(pt_path)

    result = {
        "filename": os.path.basename(pt_path),
        "file_path": os.path.abspath(pt_path),
        "file_size_mb": file_size_mb,
        "is_valid_pytorch_zip": False,
        "model_architecture": "Unknown",
        "num_classes": 0,
        "classes": {},
        "class_labels": [],
        "epochs": None,
        "training_args": {}
    }

    try:
        with zipfile.ZipFile(pt_path, 'r') as z:
            result["is_valid_pytorch_zip"] = True
            for filename in z.namelist():
                if filename.endswith('data.pkl'):
                    raw_data = z.read(filename)
                    
                    class TorchMetaUnpickler(pickle.Unpickler):
                        def persistent_load(self, pid):
                            return pid
                        def find_class(self, module, name):
                            class DummyObj:
                                def __init__(self, *args, **kwargs): pass
                                def __setstate__(self, state):
                                    if isinstance(state, dict): self.__dict__.update(state)
                                    elif isinstance(state, tuple): self.state_tuple = state
                            return DummyObj

                    unpickler = TorchMetaUnpickler(io.BytesIO(raw_data))
                    model_dict = unpickler.load()

                    if isinstance(model_dict, dict):
                        if "epoch" in model_dict:
                            result["epochs"] = model_dict["epoch"]
                        if "train_args" in model_dict:
                            result["training_args"] = model_dict["train_args"]

                        if "model" in model_dict:
                            m = model_dict["model"]
                            
                            # Extract class names dict
                            names = getattr(m, "names", None)
                            if isinstance(names, dict):
                                result["classes"] = {str(k): str(v) for k, v in names.items()}
                                result["class_labels"] = [str(v) for v in names.values()]
                                result["num_classes"] = len(names)

                            # Extract number of classes
                            nc = getattr(m, "nc", None)
                            if nc is not None:
                                result["num_classes"] = nc

                            # Extract model architecture args
                            margs = getattr(m, "args", {})
                            if isinstance(margs, dict):
                                result["model_architecture"] = margs.get("model", "YOLO11 / YOLOv8")
                                if not result["epochs"] and "epochs" in margs:
                                    result["epochs"] = margs["epochs"]
                    break
    except Exception as err:
        result["error"] = str(err)

    return result

if __name__ == "__main__":
    filepath = sys.argv[1] if len(sys.argv) > 1 else "src/assets/models/novalunch_yolo.pt"
    info = inspect_pt_file(filepath)
    print(json.dumps(info, indent=2))
