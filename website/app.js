// This isolated preview never controls device restrictions or stores visitor data.
(() => {
  const button = document.querySelector('#demo-toggle');
  const clock = document.querySelector('#clock');
  const status = document.querySelector('#demo-status');
  const progress = document.querySelector('#progress');
  if (!button || !clock || !status || !progress) return;
  let remaining = 1800, deadline = 0, running = false, started = false;
  function render() {
    const seconds = Math.max(0, Math.ceil(remaining));
    clock.textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
    progress.style.strokeDashoffset = String(678.584 * (1 - remaining / 1800));
    button.textContent = running ? 'Ⅱ  Pause preview' : remaining <= 0 ? '↻  Restart preview' : started ? '▶  Resume preview' : '▶  Try Start';
    status.textContent = running ? 'Your window is open. Make it count.' : remaining <= 0 ? 'Time’s up. Back to your day.' : started ? 'Paused. Your remaining time is saved.' : 'A little distance starts here.';
  }
  button.addEventListener('click', () => {
    if (running) { remaining = Math.max(0, (deadline - performance.now()) / 1000); running = false; }
    else { if (remaining <= 0) remaining = 1800; deadline = performance.now() + remaining * 1000; running = true; started = true; }
    render();
  });
  setInterval(() => { if (!running) return; remaining = Math.max(0, (deadline - performance.now()) / 1000); if (!remaining) running = false; render(); }, 250);
})();
