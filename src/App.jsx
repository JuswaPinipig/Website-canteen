import React, { useState } from 'react';

// Mock Data Sets
const MOCK_MENU = [
    { id: 1, name: "Boxed Pork Adobo & Rice", category: "Meals", price: 100.00, stock: "Available", img: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=400&q=80" },
    { id: 2, name: "Special Cheesy Burger", category: "Snacks", price: 40.00, stock: "Available", img: "https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=400&q=80" },
    { id: 3, name: "Creamy Boxed Pasta", category: "Meals", price: 50.00, stock: "Low Stock", img: "https://images.unsplash.com/photo-1551183053-bf91a1d81141?auto=format&fit=crop&w=400&q=80" },
    { id: 4, name: "Iced Calamansi Juice", category: "Drinks", price: 20.00, stock: "Available", img: "https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?auto=format&fit=crop&w=400&q=80" },
];

const MOCK_TRAY_LOGS = [
    { id: "TRAY-8821", time: "Today, 12:15 PM", items: ["Boxed Pasta x1", "Cheesy Burger x1"], total: 90.00, status: "Verified by YOLO AI", confidence: "96%", img: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=500&q=80" },
    { id: "TRAY-8794", time: "Yesterday, 12:10 PM", items: ["Pork Adobo & Rice x1", "Calamansi Juice x1"], total: 120.00, status: "Verified by YOLO AI", confidence: "98%", img: "https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=500&q=80" },
];

const MOCK_GCASH_QUEUE = [
    { id: "REF-9941", parent: "Maria Santos", student: "Adi Nonog", amount: 500.00, date: "2026-07-28 10:42 AM", refNo: "GCASH-9918234", status: "Pending" },
    { id: "REF-9942", parent: "Carlos Dela Cruz", student: "Juan Dela Cruz", amount: 300.00, date: "2026-07-28 11:15 AM", refNo: "GCASH-7728192", status: "Pending" },
    { id: "REF-9943", parent: "Elena Reyes", student: "Sophia Reyes", amount: 1000.00, date: "2026-07-28 11:30 AM", refNo: "GCASH-8819203", status: "Pending" }
];

export default function App() {
    const [activeRole, setActiveRole] = useState('LANDING');
    const [studentBalance, setStudentBalance] = useState(150.00);
    const [preOrders, setPreOrders] = useState([
        { id: 101, name: "Creamy Boxed Pasta", qty: 1, price: 50.00, date: "Today 12:30 PM", status: "Ready for Pickup" },
        { id: 102, name: "Cheesy Burger", qty: 1, price: 40.00, date: "Today 12:30 PM", status: "Ready for Pickup" }
    ]);
    const [posCart, setPosCart] = useState([
        { id: 1, name: "Boxed Pasta", price: 50.00, qty: 1, conf: 0.94 },
        { id: 2, name: "Cheesy Burger", price: 40.00, qty: 1, conf: 0.91 }
    ]);
    const [gcashQueue, setGcashQueue] = useState(MOCK_GCASH_QUEUE);
    const [claimModalOpen, setClaimModalOpen] = useState(false);
    const [notification, setNotification] = useState("");

    const showToast = (msg) => {
        setNotification(msg);
        setTimeout(() => setNotification(""), 4000);
    };

    const posTotal = posCart.reduce((sum, item) => sum + (item.price * item.qty), 0);

    const renderNavBar = (roleTitle) => (
        <header className="bg-[#1D0B0D] border-b border-[#3D181C] px-6 py-4 flex flex-col md:flex-row justify-between items-center gap-4 sticky top-0 z-40 shadow-xl">
            <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-full bg-[#7B1E22] border border-[#C5A059] flex items-center justify-center font-serif text-[#C5A059] font-bold text-xl shadow-md">
                    SJ
                </div>
                <div>
                    <div className="text-xs text-[#C5A059] font-semibold tracking-wider uppercase">Saint Joseph College of Novaliches, Inc.</div>
                    <div className="font-serif text-xl font-bold text-white flex items-center gap-2">
                        NovaLunch <span className="text-xs font-sans px-2 py-0.5 rounded bg-[#2A1114] border border-[#3D181C] text-[#C5A059]">{roleTitle}</span>
                    </div>
                </div>
            </div>
            <div className="flex items-center gap-4">
                <span className="text-xs text-[#EAEAEA]/70 bg-[#2A1114] border border-[#3D181C] px-3 py-1.5 rounded-full flex items-center gap-2">
                    <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span> Mode: Mock Prototype
                </span>
                <button 
                    onClick={() => { setActiveRole('LANDING'); showToast("Signed out. Returned to Landing Portal."); }}
                    className="bg-[#3D181C] hover:bg-[#7B1E22] text-[#EAEAEA] hover:text-white px-4 py-1.5 rounded-lg text-sm font-medium border border-[#7B1E22] transition-all flex items-center gap-1.5 shadow-sm"
                >
                    Sign Out ➔
                </button>
            </div>
        </header>
    );

    if (activeRole === 'LANDING') {
        return (
            <div className="min-h-screen bg-[#170808] flex flex-col justify-between text-[#EAEAEA]">
                {notification && (
                    <div className="fixed top-5 right-5 z-50 bg-[#7B1E22] text-white px-5 py-3 rounded-lg border border-[#C5A059] shadow-2xl animate-bounce text-sm">
                        {notification}
                    </div>
                )}
                <main className="flex-1 grid grid-cols-1 lg:grid-cols-12 min-h-screen">
                    <div className="lg:col-span-5 bg-[#170808] p-8 lg:p-14 flex flex-col justify-center border-r border-[#3D181C] shadow-2xl relative">
                        <div className="max-w-md mx-auto w-full space-y-8">
                            <div className="flex items-center gap-3">
                                <div className="w-12 h-12 rounded-full bg-[#7B1E22] border-2 border-[#C5A059] flex items-center justify-center text-[#C5A059] font-serif font-bold text-2xl shadow-lg">
                                    SJ
                                </div>
                                <div>
                                    <h3 className="text-[#C5A059] text-xs font-bold uppercase tracking-widest leading-tight">
                                        SAINT JOSEPH COLLEGE
                                    </h3>
                                    <p className="text-xs text-[#EAEAEA]/60 tracking-wider">of Novaliches, Inc.</p>
                                </div>
                            </div>
                            <div>
                                <h1 className="font-serif text-4xl lg:text-5xl font-bold text-white mb-2 tracking-tight">
                                    Welcome Back
                                </h1>
                                <p className="text-sm text-[#EAEAEA]/70">
                                    Select a Role Portal below to enter the NovaLunch Canteen Management System prototype.
                                </p>
                            </div>
                            <div className="space-y-4 pt-2">
                                <button
                                    onClick={() => setActiveRole('STUDENT')}
                                    className="w-full bg-[#7B1E22] hover:bg-[#99262B] text-white font-medium py-3.5 px-5 rounded-xl border border-[#C5A059]/40 hover:border-[#C5A059] transition-all duration-200 flex justify-between items-center text-left shadow-lg group"
                                >
                                    <span className="font-semibold text-base">ACCESS PORTAL ➔ (Student)</span>
                                    <span className="text-xs text-[#C5A059] bg-[#1D0B0D] px-2.5 py-1 rounded border border-[#3D181C] group-hover:border-[#C5A059]">View Pre-orders</span>
                                </button>
                                <button
                                    onClick={() => setActiveRole('PARENT')}
                                    className="w-full bg-[#7B1E22] hover:bg-[#99262B] text-white font-medium py-3.5 px-5 rounded-xl border border-[#C5A059]/40 hover:border-[#C5A059] transition-all duration-200 flex justify-between items-center text-left shadow-lg group"
                                >
                                    <span className="font-semibold text-base">ACCESS PORTAL ➔ (Parent)</span>
                                    <span className="text-xs text-[#C5A059] bg-[#1D0B0D] px-2.5 py-1 rounded border border-[#3D181C] group-hover:border-[#C5A059]">GCash & Tray Logs</span>
                                </button>
                                <button
                                    onClick={() => setActiveRole('CASHIER')}
                                    className="w-full bg-[#7B1E22] hover:bg-[#99262B] text-white font-medium py-3.5 px-5 rounded-xl border border-[#C5A059]/40 hover:border-[#C5A059] transition-all duration-200 flex justify-between items-center text-left shadow-lg group"
                                >
                                    <span className="font-semibold text-base">ACCESS PORTAL ➔ (Cashier)</span>
                                    <span className="text-xs text-[#C5A059] bg-[#1D0B0D] px-2.5 py-1 rounded border border-[#3D181C] group-hover:border-[#C5A059]">YOLO POS Review</span>
                                </button>
                                <button
                                    onClick={() => setActiveRole('ADMIN')}
                                    className="w-full bg-[#7B1E22] hover:bg-[#99262B] text-white font-medium py-3.5 px-5 rounded-xl border border-[#C5A059]/40 hover:border-[#C5A059] transition-all duration-200 flex justify-between items-center text-left shadow-lg group"
                                >
                                    <span className="font-semibold text-base">ACCESS PORTAL ➔ (Canteen Admin)</span>
                                    <span className="text-xs text-[#C5A059] bg-[#1D0B0D] px-2.5 py-1 rounded border border-[#3D181C] group-hover:border-[#C5A059]">Analytics & Approvals</span>
                                </button>
                            </div>
                            <div className="pt-6 border-t border-[#3D181C] text-xs text-[#EAEAEA]/50 flex justify-between items-center">
                                <span>NovaLunch v2.4 Capstone Prototype</span>
                                <span className="text-[#C5A059]">Academic RBAC View</span>
                            </div>
                        </div>
                    </div>
                    <div className="lg:col-span-7 bg-[#1D0B0D] p-8 lg:p-16 flex flex-col justify-between relative overflow-hidden">
                        <div className="relative z-10 flex justify-end">
                            <span className="text-xs text-[#C5A059] border border-[#C5A059]/40 px-3 py-1 rounded-full uppercase tracking-wider">
                                AI-Powered Canteen Kiosk System
                            </span>
                        </div>
                        <div className="relative z-10 max-w-2xl my-auto space-y-6">
                            <h2 className="font-serif text-3xl sm:text-5xl lg:text-6xl font-extrabold text-white leading-tight">
                                <span className="text-[#C5A059] block italic text-2xl sm:text-3xl font-normal mb-2">Welcome To</span>
                                Experience Excellence
                            </h2>
                            <div className="w-20 h-1 bg-[#C5A059]"></div>
                            <p className="font-serif text-xl sm:text-2xl text-[#EAEAEA]/90 italic font-light">
                                "Where tradition meets innovation in education."
                            </p>
                            <p className="text-sm text-[#EAEAEA]/70 leading-relaxed max-w-lg font-sans">
                                NovaLunch integrates RFID student authorization, YOLO-based optical computer vision tray scanning, and instant GCash top-up verification to streamline canteen operations.
                            </p>
                        </div>
                        <div className="relative z-10 pt-8 border-t border-[#3D181C] flex flex-col sm:flex-row justify-between items-center text-xs text-[#EAEAEA]/60 gap-4">
                            <div>© 2026 Saint Joseph College of Novaliches, Inc. All rights reserved.</div>
                            <div className="flex gap-4 text-[#C5A059]">
                                <span>RFID Integrated</span> • <span>YOLO AI Vision</span> • <span>Automated POS</span>
                            </div>
                        </div>
                    </div>
                </main>
            </div>
        );
    }

    if (activeRole === 'STUDENT') {
        return (
            <div className="min-h-screen bg-[#170808] text-[#EAEAEA]">
                {renderNavBar("Student Portal")}
                {notification && (
                    <div className="fixed top-20 right-5 z-50 bg-[#7B1E22] text-white px-5 py-3 rounded-lg border border-[#C5A059] shadow-xl text-sm">
                        {notification}
                    </div>
                )}
                <main className="max-w-7xl mx-auto p-6 space-y-6">
                    <div className="bg-[#1D0B0D] p-6 rounded-2xl border border-[#3D181C] flex flex-col md:flex-row justify-between items-start md:items-center gap-4 shadow-xl">
                        <div>
                            <h1 className="font-serif text-3xl font-bold text-white mb-1">Student Portal</h1>
                            <p className="text-sm text-[#EAEAEA]/70">Welcome back, <span className="text-white font-semibold">Adi Nonog</span> (Grade 11 - St. Joseph)</p>
                        </div>
                        <div className="bg-[#2A1114] px-6 py-3 rounded-xl border border-[#C5A059]/40 flex items-center gap-3">
                            <div>
                                <div className="text-xs text-[#EAEAEA]/60 uppercase tracking-wider">Account Balance</div>
                                <div className="font-serif text-2xl font-bold text-[#C5A059]">₱{studentBalance.toFixed(2)}</div>
                            </div>
                        </div>
                    </div>

                    <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
                        <div className="lg:col-span-7 space-y-4">
                            <div className="flex justify-between items-center">
                                <h2 className="font-serif text-xl font-bold text-white">Daily Canteen Menu</h2>
                                <span className="text-xs text-[#C5A059] bg-[#2A1114] px-3 py-1 rounded-full border border-[#3D181C]">Live Kitchen Availability</span>
                            </div>
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                {MOCK_MENU.map(item => (
                                    <div key={item.id} className="bg-[#2A1114] p-4 rounded-xl border border-[#3D181C] flex flex-col justify-between space-y-3 hover:border-[#C5A059]/50 transition-all shadow-md">
                                        <div className="relative h-32 rounded-lg overflow-hidden bg-[#1D0B0D]">
                                            <img src={item.img} alt={item.name} className="w-full h-full object-cover" />
                                            <span className="absolute top-2 right-2 text-xs bg-[#170808]/80 text-[#C5A059] px-2 py-0.5 rounded border border-[#C5A059]/40">
                                                {item.stock}
                                            </span>
                                        </div>
                                        <div>
                                            <div className="text-xs text-[#C5A059] font-medium">{item.category}</div>
                                            <h3 className="font-bold text-white text-base">{item.name}</h3>
                                        </div>
                                        <div className="flex justify-between items-center pt-2 border-t border-[#3D181C]">
                                            <div className="font-serif font-bold text-lg text-white">₱{item.price.toFixed(2)}</div>
                                            <button
                                                onClick={() => {
                                                    setPreOrders([...preOrders, { id: Date.now(), name: item.name, qty: 1, price: item.price, date: "Today 12:30 PM", status: "Queued" }]);
                                                    showToast(`Added ${item.name} to Pre-orders!`);
                                                }}
                                                className="bg-[#7B1E22] hover:bg-[#99262B] text-white text-xs font-semibold px-3 py-1.5 rounded-lg border border-[#C5A059]/30 transition-all"
                                            >
                                                + Pre-order
                                            </button>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </div>

                        <div className="lg:col-span-5 space-y-4">
                            <div className="bg-[#2A1114] p-6 rounded-2xl border border-[#3D181C] shadow-xl space-y-6">
                                <div className="flex justify-between items-center border-b border-[#3D181C] pb-4">
                                    <div>
                                        <h2 className="font-serif text-xl font-bold text-white">My Pre-Orders</h2>
                                        <p className="text-xs text-[#EAEAEA]/60">Active orders ready for mobile claim</p>
                                    </div>
                                    <span className="bg-[#7B1E22] text-white text-xs px-2.5 py-1 rounded-full font-bold">
                                        {preOrders.length} Items
                                    </span>
                                </div>

                                <div className="space-y-3 max-h-64 overflow-y-auto pr-1">
                                    {preOrders.map(order => (
                                        <div key={order.id} className="bg-[#1D0B0D] p-3.5 rounded-xl border border-[#3D181C] flex justify-between items-center">
                                            <div>
                                                <div className="font-semibold text-white text-sm">{order.name}</div>
                                                <div className="text-xs text-[#EAEAEA]/60">{order.date}</div>
                                            </div>
                                            <div className="text-right">
                                                <div className="font-serif font-bold text-sm text-[#C5A059]">₱{order.price.toFixed(2)}</div>
                                                <span className="text-[10px] text-emerald-400 bg-emerald-950/60 px-2 py-0.5 rounded border border-emerald-800">
                                                    {order.status}
                                                </span>
                                            </div>
                                        </div>
                                    ))}
                                </div>

                                <div className="pt-4 border-t border-[#3D181C] space-y-3">
                                    <div className="flex justify-between text-sm">
                                        <span className="text-[#EAEAEA]/70">Total Claim Amount:</span>
                                        <span className="font-serif font-bold text-lg text-white">
                                            ₱{preOrders.reduce((sum, o) => sum + o.price, 0).toFixed(2)}
                                        </span>
                                    </div>

                                    <button
                                        onClick={() => setClaimModalOpen(true)}
                                        className="w-full bg-[#7B1E22] hover:bg-[#99262B] text-white font-bold py-3 px-4 rounded-xl border border-[#C5A059] shadow-lg transition-all text-center flex justify-center items-center gap-2"
                                    >
                                        <span>Initiate Mobile Claim</span> ➔
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>
                </main>

                {claimModalOpen && (
                    <div className="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-4">
                        <div className="bg-[#2A1114] max-w-md w-full p-6 rounded-2xl border-2 border-[#C5A059] space-y-5 text-center shadow-2xl">
                            <div className="w-12 h-12 mx-auto rounded-full bg-[#7B1E22] text-[#C5A059] flex items-center justify-center font-bold text-xl border border-[#C5A059]">
                                RFID
                            </div>
                            <h3 className="font-serif text-2xl font-bold text-white">Mobile Claim Activated</h3>
                            <p className="text-xs text-[#EAEAEA]/70">
                                Tap your RFID Student ID Card at NovaLunch Kiosk #01 or scan this QR token on the tray camera scanner.
                            </p>
                            <div className="bg-white p-4 rounded-xl w-48 h-48 mx-auto flex flex-col items-center justify-center border-4 border-[#7B1E22]">
                                <div className="w-36 h-36 bg-gray-900 rounded grid grid-cols-4 gap-1 p-2">
                                    {[...Array(16)].map((_, i) => (
                                        <div key={i} className={`rounded-sm ${i % 2 === 0 ? 'bg-white' : 'bg-transparent'}`}></div>
                                    ))}
                                </div>
                                <span className="text-[10px] text-gray-800 font-mono font-bold mt-1">TOKEN: SJ-883921</span>
                            </div>
                            <button
                                onClick={() => {
                                    setClaimModalOpen(false);
                                    showToast("Kiosk claim verified successfully!");
                                }}
                                className="w-full bg-[#7B1E22] hover:bg-[#99262B] text-white font-bold py-2.5 rounded-xl border border-[#C5A059]"
                            >
                                Close Claim Simulation
                            </button>
                        </div>
                    </div>
                )}
            </div>
        );
    }

    if (activeRole === 'PARENT') {
        return (
            <div className="min-h-screen bg-[#170808] text-[#EAEAEA]">
                {renderNavBar("Parent Oversight Portal")}
                {notification && (
                    <div className="fixed top-20 right-5 z-50 bg-[#7B1E22] text-white px-5 py-3 rounded-lg border border-[#C5A059] shadow-xl text-sm">
                        {notification}
                    </div>
                )}
                <main className="max-w-7xl mx-auto p-6 space-y-6">
                    <div className="bg-[#1D0B0D] p-6 rounded-2xl border border-[#3D181C] flex flex-col md:flex-row justify-between items-start md:items-center gap-4 shadow-xl">
                        <div>
                            <h1 className="font-serif text-3xl font-bold text-white mb-1">Parent Oversight Portal</h1>
                            <p className="text-sm text-[#EAEAEA]/70">Managing Student: <span className="text-[#C5A059] font-semibold">Adi Nonog</span> (ID: 2026-883921)</p>
                        </div>
                        <div className="bg-[#2A1114] px-4 py-2 rounded-xl border border-[#3D181C] text-right">
                            <div className="text-[10px] text-[#EAEAEA]/60 uppercase">Current Balance</div>
                            <div className="font-serif font-bold text-xl text-[#C5A059]">₱{studentBalance.toFixed(2)}</div>
                        </div>
                    </div>

                    <div className="bg-[#2A1114] p-6 rounded-2xl border border-[#3D181C] shadow-xl space-y-4">
                        <div className="border-b border-[#3D181C] pb-3 flex justify-between items-center">
                            <div>
                                <h2 className="font-serif text-lg font-bold text-white">GCash Account Reload</h2>
                                <p className="text-xs text-[#EAEAEA]/60">Upload proof of payment to reload student RFID card balance</p>
                            </div>
                            <span className="text-xs text-[#C5A059] bg-[#1D0B0D] px-3 py-1 rounded border border-[#3D181C]">
                                GCash No: 0917-882-9901
                            </span>
                        </div>

                        <form onSubmit={(e) => {
                            e.preventDefault();
                            showToast("GCash Receipt Proof submitted for Admin verification!");
                        }} className="grid grid-cols-1 md:grid-cols-3 gap-4 items-end">
                            <div>
                                <label className="block text-xs text-[#EAEAEA]/70 mb-1.5">Top-Up Amount (₱)</label>
                                <input type="number" defaultValue="500" className="w-full bg-[#1D0B0D] border border-[#3D181C] rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-[#C5A059]" />
                            </div>
                            <div>
                                <label className="block text-xs text-[#EAEAEA]/70 mb-1.5">Upload Receipt Proof (Image/PDF)</label>
                                <input type="file" className="w-full bg-[#1D0B0D] border border-[#3D181C] rounded-lg px-3 py-1.5 text-xs text-[#EAEAEA]/70 file:mr-2 file:py-1 file:px-2 file:rounded file:border-0 file:text-xs file:bg-[#3D181C] file:text-[#C5A059]" />
                            </div>
                            <div>
                                <button type="submit" className="w-full bg-[#7B1E22] hover:bg-[#99262B] text-white font-bold py-2.5 px-4 rounded-lg border border-[#C5A059] text-sm transition-all shadow-md">
                                    Upload GCash Receipt Proof
                                </button>
                            </div>
                        </form>
                    </div>

                    <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
                        <div className="lg:col-span-7 space-y-4">
                            <h2 className="font-serif text-xl font-bold text-white flex items-center justify-between">
                                <span>Visual Tray Log</span>
                                <span className="text-xs font-sans text-[#C5A059] font-normal">AI Camera Tray Verifications</span>
                            </h2>

                            <div className="space-y-4">
                                {MOCK_TRAY_LOGS.map(log => (
                                    <div key={log.id} className="bg-[#2A1114] p-5 rounded-2xl border border-[#3D181C] shadow-lg flex flex-col md:flex-row gap-4 hover:border-[#C5A059]/40 transition-all">
                                        <div className="w-full md:w-44 h-32 rounded-xl bg-[#1D0B0D] overflow-hidden border border-[#3D181C] shrink-0">
                                            <img src={log.img} alt="Tray Photo" className="w-full h-full object-cover" />
                                        </div>
                                        <div className="flex-1 flex flex-col justify-between space-y-2">
                                            <div>
                                                <div className="flex justify-between items-center mb-1">
                                                    <span className="font-mono text-xs text-[#C5A059] font-bold">{log.id}</span>
                                                    <span className="text-xs text-[#EAEAEA]/60">{log.time}</span>
                                                </div>
                                                <ul className="text-sm text-white space-y-1">
                                                    {log.items.map((it, idx) => (
                                                        <li key={idx} className="flex items-center gap-2">
                                                            <span className="w-1.5 h-1.5 rounded-full bg-[#C5A059]"></span> {it}
                                                        </li>
                                                    ))}
                                                </ul>
                                            </div>

                                            <div className="pt-2 border-t border-[#3D181C] flex justify-between items-center">
                                                <div className="text-xs text-emerald-400 bg-emerald-950/60 px-2 py-0.5 rounded border border-emerald-800">
                                                    {log.status} ({log.confidence})
                                                </div>
                                                <div className="font-serif font-bold text-white">Total: ₱{log.total.toFixed(2)}</div>
                                            </div>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </div>

                        <div className="lg:col-span-5 space-y-4">
                            <div className="bg-[#2A1114] p-6 rounded-2xl border border-[#3D181C] shadow-xl space-y-4">
                                <div className="border-b border-[#3D181C] pb-3">
                                    <h2 className="font-serif text-lg font-bold text-white">Advance Pre-Ordering</h2>
                                    <p className="text-xs text-[#EAEAEA]/60">Schedule student lunches for upcoming weekdays</p>
                                </div>

                                <div className="space-y-3">
                                    {["Monday (Adobo + Juice)", "Tuesday (Boxed Pasta)", "Wednesday (Burger Meal)", "Thursday (Chicken Meal)", "Friday (Fish Fillet + Rice)"].map((day, idx) => (
                                        <div key={idx} className="bg-[#1D0B0D] p-3 rounded-xl border border-[#3D181C] flex justify-between items-center">
                                            <div className="text-xs text-white font-medium">{day}</div>
                                            <input type="checkbox" defaultChecked={idx < 2} className="w-4 h-4 accent-[#7B1E22] rounded cursor-pointer" />
                                        </div>
                                    ))}
                                </div>

                                <button
                                    onClick={() => showToast("Weekly pre-orders saved successfully!")}
                                    className="w-full bg-[#7B1E22] hover:bg-[#99262B] text-white font-bold py-2.5 rounded-xl border border-[#C5A059] text-xs transition-all"
                                >
                                    Save Weekly Meal Plan
                                </button>
                            </div>
                        </div>
                    </div>
                </main>
            </div>
        );
    }

    if (activeRole === 'CASHIER') {
        return (
            <div className="min-h-screen bg-[#170808] text-[#EAEAEA]">
                {renderNavBar("Cashier POS Terminal")}
                {notification && (
                    <div className="fixed top-20 right-5 z-50 bg-[#7B1E22] text-white px-5 py-3 rounded-lg border border-[#C5A059] shadow-xl text-sm">
                        {notification}
                    </div>
                )}
                <main className="max-w-7xl mx-auto p-6 space-y-6">
                    <div className="bg-[#1D0B0D] p-6 rounded-2xl border border-[#3D181C] flex justify-between items-center shadow-xl">
                        <div>
                            <h1 className="font-serif text-3xl font-bold text-white mb-1">Cashier Terminal (Web View)</h1>
                            <p className="text-sm text-[#EAEAEA]/70">Live Terminal ID: <span className="text-[#C5A059] font-mono">POS-NOV-01</span></p>
                        </div>
                        <span className="bg-emerald-950 text-emerald-400 text-xs px-3 py-1.5 rounded-full border border-emerald-800 flex items-center gap-2">
                            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-ping"></span> YOLO AI Engine Connected
                        </span>
                    </div>

                    <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
                        <div className="lg:col-span-7 bg-[#2A1114] p-6 rounded-2xl border border-[#3D181C] shadow-xl space-y-6">
                            <div className="flex justify-between items-center border-b border-[#3D181C] pb-4">
                                <div>
                                    <h2 className="font-serif text-xl font-bold text-white">Live YOLO AI Cart Review</h2>
                                    <p className="text-xs text-[#EAEAEA]/60">Items automatically detected from Kiosk optical tray camera</p>
                                </div>
                                <span className="text-xs text-[#C5A059] bg-[#1D0B0D] px-2.5 py-1 rounded border border-[#3D181C]">
                                    2 Items Detected
                                </span>
                            </div>

                            <div className="space-y-3">
                                {posCart.map(item => (
                                    <div key={item.id} className="bg-[#1D0B0D] p-4 rounded-xl border border-[#3D181C] flex justify-between items-center">
                                        <div>
                                            <div className="font-bold text-white text-base">{item.name}</div>
                                            <div className="text-xs text-[#C5A059]">AI Confidence: {Math.round(item.conf * 100)}%</div>
                                        </div>

                                        <div className="flex items-center gap-4">
                                            <div className="font-serif font-bold text-lg text-white">₱{(item.price * item.qty).toFixed(2)}</div>
                                            <div className="flex items-center border border-[#3D181C] rounded-lg bg-[#2A1114] overflow-hidden">
                                                <button 
                                                    onClick={() => {
                                                        if (item.qty > 1) {
                                                            setPosCart(posCart.map(i => i.id === item.id ? { ...i, qty: i.qty - 1 } : i));
                                                        }
                                                    }} 
                                                    className="px-3 py-1 text-[#C5A059] hover:bg-[#7B1E22] font-bold"
                                                >-</button>
                                                <span className="px-3 text-xs text-white font-bold">{item.qty}</span>
                                                <button 
                                                    onClick={() => {
                                                        setPosCart(posCart.map(i => i.id === item.id ? { ...i, qty: i.qty + 1 } : i));
                                                    }} 
                                                    className="px-3 py-1 text-[#C5A059] hover:bg-[#7B1E22] font-bold"
                                                >+</button>
                                            </div>
                                            <button 
                                                onClick={() => setPosCart(posCart.filter(i => i.id !== item.id))} 
                                                className="text-xs text-[#DC3545] hover:text-white bg-[#3D181C] hover:bg-[#7B1E22] px-2.5 py-1.5 rounded border border-[#3D181C]"
                                            >
                                                Delete
                                            </button>
                                        </div>
                                    </div>
                                ))}
                            </div>

                            <div className="pt-4 border-t border-[#3D181C] flex justify-between items-center">
                                <span className="text-lg font-serif font-bold text-white">Cart Total:</span>
                                <span className="text-3xl font-serif font-extrabold text-[#C5A059]">₱{posTotal.toFixed(2)}</span>
                            </div>
                        </div>

                        <div className="lg:col-span-5 space-y-6">
                            <div className="bg-[#2A1114] p-6 rounded-2xl border border-[#3D181C] shadow-xl space-y-4">
                                <h2 className="font-serif text-lg font-bold text-white border-b border-[#3D181C] pb-3">
                                    Incoming Pre-Order Claims
                                </h2>
                                <div className="bg-[#1D0B0D] p-3.5 rounded-xl border border-[#3D181C] space-y-2">
                                    <div className="flex justify-between text-xs">
                                        <span className="text-white font-semibold">Adi Nonog (Claim #4091)</span>
                                        <span className="text-emerald-400 font-bold">Ready</span>
                                    </div>
                                    <p className="text-xs text-[#EAEAEA]/60">Boxed Pasta x1, Cheesy Burger x1</p>
                                </div>
                            </div>

                            <div className="bg-[#2A1114] p-6 rounded-2xl border border-[#3D181C] shadow-xl space-y-4">
                                <button
                                    onClick={() => showToast("Transaction tagged as Pay Later (Financial Aid Credit Logged)!")}
                                    className="w-full bg-[#7B1E22] hover:bg-[#99262B] text-white font-bold py-3.5 px-4 rounded-xl border border-[#C5A059] shadow-lg transition-all text-sm"
                                >
                                    Tag Transaction as Pay Later
                                </button>

                                <button
                                    onClick={() => {
                                        showToast("POS Transaction Settled Successfully!");
                                        setPosCart([]);
                                    }}
                                    className="w-full bg-emerald-900 hover:bg-emerald-800 text-white font-bold py-3.5 px-4 rounded-xl border border-emerald-600 shadow-lg transition-all text-sm"
                                >
                                    Complete Transaction & Print Receipt
                                </button>
                            </div>
                        </div>
                    </div>
                </main>
            </div>
        );
    }

    if (activeRole === 'ADMIN') {
        return (
            <div className="min-h-screen bg-[#170808] text-[#EAEAEA]">
                {renderNavBar("Canteen Admin Dashboard")}
                {notification && (
                    <div className="fixed top-20 right-5 z-50 bg-[#7B1E22] text-white px-5 py-3 rounded-lg border border-[#C5A059] shadow-xl text-sm">
                        {notification}
                    </div>
                )}
                <main className="max-w-7xl mx-auto p-6 space-y-6">
                    <div className="bg-[#1D0B0D] p-6 rounded-2xl border border-[#3D181C] flex justify-between items-center shadow-xl">
                        <div>
                            <h1 className="font-serif text-3xl font-bold text-white mb-1">Canteen Management & Analytics</h1>
                            <p className="text-sm text-[#EAEAEA]/70">Executive Overview & Parent Top-Up Verifications</p>
                        </div>
                        <span className="text-xs text-[#C5A059] bg-[#2A1114] px-4 py-2 rounded-xl border border-[#3D181C]">
                            Academic Year 2025-2026
                        </span>
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                        <div className="bg-[#2A1114] p-5 rounded-2xl border border-[#3D181C] shadow-lg">
                            <div className="text-xs text-[#EAEAEA]/60 uppercase tracking-wider">Total Sales Today</div>
                            <div className="font-serif text-2xl font-bold text-white mt-1">₱24,850.00</div>
                            <div className="text-[10px] text-emerald-400 mt-2">+14% vs yesterday</div>
                        </div>

                        <div className="bg-[#2A1114] p-5 rounded-2xl border border-[#3D181C] shadow-lg">
                            <div className="text-xs text-[#EAEAEA]/60 uppercase tracking-wider">Fast-Moving Item</div>
                            <div className="font-serif text-xl font-bold text-[#C5A059] mt-1">Boxed Pasta</div>
                            <div className="text-[10px] text-[#EAEAEA]/60 mt-2">342 portions sold</div>
                        </div>

                        <div className="bg-[#2A1114] p-5 rounded-2xl border border-[#3D181C] shadow-lg">
                            <div className="text-xs text-[#EAEAEA]/60 uppercase tracking-wider">Low Stock Alerts</div>
                            <div className="font-serif text-xl font-bold text-[#DC3545] mt-1">Boxed Pasta &lt; 10%</div>
                            <div className="text-[10px] text-[#DC3545] mt-2">8 portions remaining</div>
                        </div>

                        <div className="bg-[#2A1114] p-5 rounded-2xl border border-[#3D181C] shadow-lg">
                            <div className="text-xs text-[#EAEAEA]/60 uppercase tracking-wider">Pending Top-Ups</div>
                            <div className="font-serif text-2xl font-bold text-white mt-1">{gcashQueue.filter(q => q.status === 'Pending').length} Receipts</div>
                            <div className="text-[10px] text-[#C5A059] mt-2">Requires verification</div>
                        </div>
                    </div>

                    <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
                        <div className="lg:col-span-7 bg-[#2A1114] p-6 rounded-2xl border border-[#3D181C] shadow-xl space-y-4">
                            <h2 className="font-serif text-xl font-bold text-white border-b border-[#3D181C] pb-3">
                                GCash Top-Up Verification Queue
                            </h2>

                            <div className="overflow-x-auto">
                                <table className="w-full text-left text-xs">
                                    <thead>
                                        <tr className="border-b border-[#3D181C] text-[#C5A059] uppercase">
                                            <th className="py-2.5 px-3">Parent</th>
                                            <th className="py-2.5 px-3">Student</th>
                                            <th className="py-2.5 px-3">Amount</th>
                                            <th className="py-2.5 px-3">Ref No.</th>
                                            <th className="py-2.5 px-3 text-right">Actions</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-[#3D181C]">
                                        {gcashQueue.map(item => (
                                            <tr key={item.id} className="hover:bg-[#1D0B0D] transition-colors">
                                                <td className="py-3 px-3 font-semibold text-white">{item.parent}</td>
                                                <td className="py-3 px-3 text-[#EAEAEA]/80">{item.student}</td>
                                                <td className="py-3 px-3 font-serif font-bold text-[#C5A059]">₱{item.amount.toFixed(2)}</td>
                                                <td className="py-3 px-3 font-mono text-[10px] text-[#EAEAEA]/60">{item.refNo}</td>
                                                <td className="py-3 px-3 text-right space-x-2">
                                                    {item.status === 'Pending' ? (
                                                        <>
                                                            <button
                                                                onClick={() => {
                                                                    setGcashQueue(gcashQueue.map(q => q.id === item.id ? { ...q, status: 'Approved' } : q));
                                                                    setStudentBalance(studentBalance + item.amount);
                                                                    showToast(`Approved ₱${item.amount} Top-Up for ${item.student}!`);
                                                                }}
                                                                className="bg-[#C5A059] hover:bg-[#D4AF67] text-[#170808] font-bold px-2.5 py-1 rounded transition-all"
                                                            >
                                                                Approve
                                                            </button>
                                                            <button
                                                                onClick={() => {
                                                                    setGcashQueue(gcashQueue.map(q => q.id === item.id ? { ...q, status: 'Rejected' } : q));
                                                                    showToast(`Rejected top-up ${item.refNo}`);
                                                                }}
                                                                className="bg-[#3D181C] hover:bg-[#7B1E22] text-white px-2.5 py-1 rounded transition-all"
                                                            >
                                                                Reject
                                                            </button>
                                                        </>
                                                    ) : (
                                                        <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${item.status === 'Approved' ? 'bg-emerald-950 text-emerald-400 border border-emerald-800' : 'bg-red-950 text-red-400 border border-red-800'}`}>
                                                            {item.status}
                                                        </span>
                                                    )}
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        </div>

                        <div className="lg:col-span-5 bg-[#2A1114] p-6 rounded-2xl border border-[#3D181C] shadow-xl space-y-4">
                            <h2 className="font-serif text-xl font-bold text-white border-b border-[#3D181C] pb-3">
                                Pre-Order Aggregation (Kitchen Prep)
                            </h2>

                            <div className="space-y-3">
                                {[
                                    { item: "Creamy Boxed Pasta", count: 120, target: 150 },
                                    { item: "Cheesy Burgers", count: 85, target: 100 },
                                    { item: "Pork Adobo Meals", count: 140, target: 140 },
                                    { item: "Iced Calamansi Juice", count: 200, target: 200 }
                                ].map((prep, i) => (
                                    <div key={i} className="bg-[#1D0B0D] p-3.5 rounded-xl border border-[#3D181C] space-y-1.5">
                                        <div className="flex justify-between text-xs font-semibold text-white">
                                            <span>{prep.item}</span>
                                            <span className="text-[#C5A059]">{prep.count} / {prep.target} units</span>
                                        </div>
                                        <div className="w-full h-2 bg-[#2A1114] rounded-full overflow-hidden border border-[#3D181C]">
                                            <div className="h-full bg-[#7B1E22]" style={{ width: `${(prep.count / prep.target) * 100}%` }}></div>
                                        </div>
                                    </div>
                                ))}
                            </div>

                            <button
                                onClick={() => showToast("Generated Daily Kitchen Prep Sheet PDF!")}
                                className="w-full bg-[#7B1E22] hover:bg-[#99262B] text-white font-bold py-2.5 rounded-xl border border-[#C5A059] text-xs transition-all"
                            >
                                Print Kitchen Prep Sheet
                            </button>
                        </div>
                    </div>
                </main>
            </div>
        );
    }

    return null;
}
