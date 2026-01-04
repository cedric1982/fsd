async function loadStatus() {
    const res = await fetch('/api/status');
    const data = await res.json();
    document.getElementById('status').innerText = data.status;
    document.getElementById('pid').innerText = data.pid || '-';
    document.getElementById('uptime').innerText = data.uptime || '-';
    document.getElementById('status-box').style.background =
        data.status === 'running' ? '#c8f7c5' : '#f7c5c5';
}

async function loadClients() {
    const res = await fetch('/api/clients');
    const data = await res.json();
    const tbody = document.querySelector('#clients tbody');
    tbody.innerHTML = '';
    data.forEach(c => {
        const row = `<tr>
            <td>${c.callsign}</td>
            <td>${c.type}</td>
            <td>${c.lat}</td>
            <td>${c.lon}</td>
            <td>${c.alt}</td>
        </tr>`;
        tbody.innerHTML += row;
    });
}


async function loadLogins() {
    const res = await fetch('/api/logins');
    const data = await res.json();
    const tbody = document.querySelector('#logins tbody');
    tbody.innerHTML = '';
    data.forEach(l => {
        const row = `<tr>
            <td>${l.timestamp}</td>
            <td>${l.callsign}</td>
            <td>${l.cid}</td>
            <td>${l.status}</td>
            <td>${l.message}</td>
        </tr>`;
        tbody.innerHTML += row;
    });
}




document.getElementById('restart').addEventListener('click', async () => {
    const res = await fetch('/api/restart', { method: 'POST' });
    const msg = await res.json();
    alert(msg.message);
    setTimeout(loadStatus, 3000);
});

setInterval(() => {
    loadStatus();
    loadClients();
    loadLogins();
}, 3000);

loadStatus();
loadClients();
loadLogins();
