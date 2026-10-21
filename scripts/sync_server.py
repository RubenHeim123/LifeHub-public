from fastapi import FastAPI, HTTPException, Request
import json
import os
from datetime import datetime

app = FastAPI(title="LifeHub Sync Server")

# Directory where backups will be saved
BACKUP_DIR = "app_backups"
if not os.path.exists(BACKUP_DIR):
    os.makedirs(BACKUP_DIR)

@app.get("/status")
async def status():
    return {"status": "online", "message": "LifeHub Sync Server is running"}

@app.post("/sync")
async def sync_data(request: Request):
    try:
        data = await request.json()
        
        # Simple validation
        sync_type = data.get("sync_type", "full")
        
        # Save to file
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{BACKUP_DIR}/sync_{sync_type}_{timestamp}.json"
        
        # Count items
        total_items = 0
        syncable_keys = [
            "accounts", "categories", "transactions", "fixed_transactions", 
            "todos", "appointments", "habits", "habit_records", "financial_goals",
            "vision_areas", "vision_goals", "goal_steps"
        ]
        for key in syncable_keys:
            if key in data and isinstance(data[key], list):
                total_items += len(data[key])
        
        with open(filename, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4, ensure_ascii=False)
            
        print(f"[*] Received {sync_type.upper()} sync: {filename} ({total_items} items)")
        return {
            "status": "success", 
            "file": filename, 
            "sync_type": sync_type,
            "items_received": total_items
        }
        
    except Exception as e:
        print(f"[!] Error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    # Start server on all interfaces so the phone can reach it
    uvicorn.run(app, host="0.0.0.0", port=8000)
