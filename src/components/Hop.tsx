export default function Hop({level}:{level:'green'|'yellow'|'red'}) {
  const fill = level==='green'?'#16a34a':level==='yellow'?'#eab308':'#dc2626'
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" aria-label="stock" xmlns="http://www.w3.org/2000/svg">
      <path d="M12 2c-1.5 1.2-4 2.3-4 5 0 2.2 2 3.3 4 4 2-0.7 4-1.8 4-4 0-2.7-2.5-3.8-4-5zm0 9c-2 0.7-4 1.8-4 4 0 3 3 5 4 7 1-2 4-4 4-7 0-2.2-2-3.3-4-4z" fill={fill}/>
      <circle cx="12" cy="12" r="11" fill="none"/>
    </svg>
  )
}
