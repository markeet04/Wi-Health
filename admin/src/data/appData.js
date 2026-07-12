export const adminPages = ['Statistics / Analytics', 'User Management', 'Alerts', 'Complaints', 'Settings']

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
