import hashlib
import requests
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, Integer, String, Double, Text, TIMESTAMP, ForeignKey, func
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session

# Conexión actualizada a la base de datos 'asistencia_gps'
DATABASE_URL = "mysql+pymysql://root:@localhost:3306/asistencia_gps"

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# Modelos de SQLAlchemy
class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True)
    password = Column(String(32))
    role = Column(String(20), default="student")

class Attendance(Base):
    __tablename__ = "attendance"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    latitude = Column(Double)
    longitude = Column(Double)
    address = Column(Text)
    created_at = Column(TIMESTAMP, server_default=func.now())

Base.metadata.create_all(bind=engine)

app = FastAPI()

# Configuración de CORS para permitir peticiones desde Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Modelos Pydantic para validación de entrada
class RegisterModel(BaseModel):
    username: str
    password: str
    role: str = "student"

class LoginModel(BaseModel):
    username: str
    password: str

class AttendanceModel(BaseModel):
    user_id: int
    latitude: float
    longitude: float

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def md5_hash(text: str) -> str:
    return hashlib.md5(text.encode()).hexdigest()

@app.post("/register/")
def register(user: RegisterModel, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.username == user.username).first()
    if existing:
        raise HTTPException(status_code=400, detail="El usuario ya existe")
    
    new_user = User(
        username=user.username,
        password=md5_hash(user.password),
        role=user.role
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return {"message": "Usuario registrado correctamente", "user_id": new_user.id}

@app.post("/login/")
def login(credentials: LoginModel, db: Session = Depends(get_db)):
    hashed_pw = md5_hash(credentials.password)
    user = db.query(User).filter(
        User.username == credentials.username,
        User.password == hashed_pw
    ).first()
    
    if not user:
        raise HTTPException(status_code=401, detail="Credenciales incorrectas")
    
    return {
        "message": "Login exitoso",
        "user_id": user.id,
        "username": user.username,
        "role": user.role
    }

@app.post("/attendance/")
def register_attendance(data: AttendanceModel, db: Session = Depends(get_db)):
    # Consulta a la API pública de Nominatim
    url = f"https://nominatim.openstreetmap.org/reverse?format=json&lat={data.latitude}&lon={data.longitude}"
    headers = {"User-Agent": "FlutterAttendanceApp/1.0"}
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        geo_data = response.json()
        address = geo_data.get("display_name", "Dirección no encontrada")
    except Exception:
        address = f"Lat: {data.latitude}, Lon: {data.longitude}"

    record = Attendance(
        user_id=data.user_id,
        latitude=data.latitude,
        longitude=data.longitude,
        address=address
    )
    db.add(record)
    db.commit()
    db.refresh(record)
    
    return {
        "message": "Asistencia registrada",
        "address": address,
        "id": record.id
    }

# Endpoint GET para cumplir con el Reto 1 (Historial de asistencias)
@app.get("/attendance/")
def get_attendance_history(user_id: int = None, db: Session = Depends(get_db)):
    if user_id:
        records = db.query(Attendance).filter(Attendance.user_id == user_id).order_by(Attendance.id.desc()).all()
    else:
        records = db.query(Attendance).order_by(Attendance.id.desc()).all()
    return records