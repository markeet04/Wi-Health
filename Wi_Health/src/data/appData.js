export const adminPages = ['Statistics / Analytics', 'User Management', 'Alerts', 'Complaints', 'Settings']

export const userPages = ['Overview', 'Patients', 'Analytics', 'Alerts', 'Support', 'Settings']

export const fleetDevices = [
  { id: 'WH-2101', patient: 'Patient A', status: 'Online', health: 'Good', updated: '10s ago' },
  { id: 'WH-2102', patient: 'Patient B', status: 'Online', health: 'Good', updated: '16s ago' },
  { id: 'WH-2103', patient: 'Patient C', status: 'Offline', health: 'Needs check', updated: '8m ago' },
  { id: 'WH-2104', patient: 'Patient D', status: 'Online', health: 'Warning', updated: '35s ago' },
]

export const users = [
  { name: 'Anita Rao', role: 'App User', patients: '2 linked', devices: 'WH-2101, WH-2102', status: 'Active' },
  { name: 'Mohan Iyer', role: 'App User', patients: '1 linked', devices: 'WH-2104', status: 'Active' },
  { name: 'Admin Ops', role: 'Admin', patients: '-', devices: 'All devices', status: 'Active' },
  { name: 'Leela Das', role: 'App User', patients: '1 linked', devices: 'WH-2103', status: 'Pending verification' },
]

export const alerts = [
  { time: '11:12 AM', patient: 'Patient D', device: 'WH-2104', anomaly: 'Tachypnea', severity: 'Urgent', status: 'Open' },
  { time: '10:50 AM', patient: 'Patient B', device: 'WH-2102', anomaly: 'Bradypnea', severity: 'Info', status: 'Acknowledged' },
  { time: '09:41 AM', patient: 'Patient C', device: 'WH-2103', anomaly: 'No valid breathing', severity: 'Urgent', status: 'In review' },
  { time: '09:08 AM', patient: 'Patient A', device: 'WH-2101', anomaly: 'Tachypnea', severity: 'Info', status: 'Resolved' },
]

export const complaints = [
  { id: 'CMP-102', user: 'Anita Rao', patient: 'Patient A', issue: 'Frequent disconnect alerts', status: 'Open', submitted: 'Today, 10:02 AM' },
  { id: 'CMP-101', user: 'Leela Das', patient: 'Patient C', issue: 'Pairing failed after restart', status: 'In-progress', submitted: 'Today, 08:45 AM' },
  { id: 'CMP-097', user: 'Mohan Iyer', patient: 'Patient D', issue: 'Delayed notifications', status: 'Resolved', submitted: 'Yesterday, 07:38 PM' },
]

export const userPatients = [
  {
    name: 'Patient A',
    device: 'WH-2101',
    caregiver: 'Anita Rao',
    rate: '18',
    state: 'Stable breathing',
    confidence: 94,
    signal: 'Good signal',
    connection: 'Online',
    update: '8s ago',
    room: 'Bedroom monitor',
    battery: '86%',
    trend: [42, 48, 55, 52, 58, 63, 60, 68],
    summary: '1 informational alert today',
  },
  {
    name: 'Patient B',
    device: 'WH-2102',
    caregiver: 'Mohan Iyer',
    rate: '22',
    state: 'Tachypnea watch',
    confidence: 81,
    signal: 'Watch signal',
    connection: 'Online',
    update: '14s ago',
    room: 'Living room monitor',
    battery: '72%',
    trend: [40, 42, 47, 51, 56, 61, 66, 70],
    summary: '2 alerts today',
  },
  {
    name: 'Patient C',
    device: 'WH-2103',
    caregiver: 'Leela Das',
    rate: '--',
    state: 'No valid breathing',
    confidence: 38,
    signal: 'Low signal',
    connection: 'Intermittent',
    update: '2m ago',
    room: 'Guest room monitor',
    battery: '61%',
    trend: [12, 18, 22, 20, 16, 14, 12, 10],
    summary: '1 missing window',
  },
  {
    name: 'Patient D',
    device: 'WH-2104',
    caregiver: 'Ravi Kumar',
    rate: '14',
    state: 'Normal rhythm',
    confidence: 89,
    signal: 'Good signal',
    connection: 'Online',
    update: '26s ago',
    room: 'Study monitor',
    battery: '91%',
    trend: [30, 34, 38, 42, 44, 46, 48, 50],
    summary: '0 critical alerts',
  },
]

export const userSessions = [
  { session: 'Tonight', patient: 'Patient A', avg: '18.2', duration: '6h 12m', lowSignal: '2 windows', anomalies: '0', quality: '94%' },
  { session: 'Earlier today', patient: 'Patient B', avg: '21.7', duration: '3h 48m', lowSignal: '1 window', anomalies: '1', quality: '87%' },
  { session: 'Yesterday', patient: 'Patient C', avg: '--', duration: '1h 09m', lowSignal: '4 windows', anomalies: '2', quality: '62%' },
  { session: 'Yesterday', patient: 'Patient D', avg: '14.6', duration: '7h 04m', lowSignal: '0 windows', anomalies: '0', quality: '96%' },
]

export const userAlerts = [
  { time: '11:14 PM', patient: 'Patient B', device: 'WH-2102', anomaly: 'Tachypnea', severity: 'Urgent', status: 'Open' },
  { time: '10:43 PM', patient: 'Patient A', device: 'WH-2101', anomaly: 'Signal restored', severity: 'Info', status: 'Acknowledged' },
  { time: '09:58 PM', patient: 'Patient C', device: 'WH-2103', anomaly: 'No valid breathing', severity: 'Urgent', status: 'In review' },
  { time: '08:32 PM', patient: 'Patient D', device: 'WH-2104', anomaly: 'Normal update', severity: 'Info', status: 'Resolved' },
]

export const supportTickets = [
  { id: 'SR-204', patient: 'Patient A', subject: 'Device disconnected after Wi-Fi reset', status: 'Open', updated: 'Today, 09:12 PM' },
  { id: 'SR-203', patient: 'Patient B', subject: 'Need help re-linking device path', status: 'In-progress', updated: 'Today, 05:40 PM' },
  { id: 'SR-198', patient: 'Patient D', subject: 'Notification arrived late', status: 'Resolved', updated: 'Yesterday, 07:03 PM' },
]