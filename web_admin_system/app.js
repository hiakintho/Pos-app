import { initializeApp, deleteApp } from "https://www.gstatic.com/firebasejs/10.13.2/firebase-app.js";
import {
  getAuth,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  signOut,
} from "https://www.gstatic.com/firebasejs/10.13.2/firebase-auth.js";
import {
  getFirestore,
  collection,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  deleteDoc,
  query,
  where,
  orderBy,
  limit,
  serverTimestamp,
} from "https://www.gstatic.com/firebasejs/10.13.2/firebase-firestore.js";

const firebaseConfig = {
  apiKey: "AIzaSyCmDcw8rZRVvKo-sBbsGQzRUW-pk3_k0k4",
  authDomain: "rubenpos-dfd96.firebaseapp.com",
  projectId: "rubenpos-dfd96",
  storageBucket: "rubenpos-dfd96.firebasestorage.app",
  messagingSenderId: "851638102781",
  appId: "1:851638102781:web:c55acbd3cc82c9e9f0ec94",
  measurementId: "G-0KW0W2VBM1",
};

const features = [
  ["dashboard", "Dashboard", "View business overview"],
  ["pos", "POS", "Sell products and complete checkout"],
  ["inventory", "Inventory", "View product stock"],
  ["add_product", "Add Product", "Create new products"],
  ["purchase_stock", "Purchase Stock", "Restock products"],
  ["reports", "Reports", "View reports and analytics"],
  ["settings", "Settings", "Open administration settings"],
  ["user_management", "User Management", "Add and edit staff"],
  ["role_management", "Role Management", "Create roles and permissions"],
  ["branch_management", "Branch Management", "Manage business locations"],
];

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

const state = {
  firebaseUser: null,
  appUser: null,
  business: null,
  businessId: null,
  page: "overview",
  branches: [],
  users: [],
  roles: [],
  products: [],
  sales: [],
  businesses: [],
  bootstrappingSuperAdmin: false,
};

const $ = (id) => document.getElementById(id);
const money = new Intl.NumberFormat("sw-TZ", {
  style: "currency",
  currency: "TZS",
  maximumFractionDigits: 0,
});

function slug(value) {
  return value.trim().toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
}

function roleDocId(businessId, roleId) {
  return `${businessId}_${roleId}`;
}

function setMessage(message) {
  $("authMessage").textContent = message || "";
}

function showAuth(mode = "login") {
  const selectedMode = mode === "super" ? "super" : "login";
  $("loginTab").classList.toggle("active", selectedMode === "login");
  $("superAdminTab").classList.toggle("active", selectedMode === "super");
  $("loginForm").classList.toggle("hidden", selectedMode !== "login");
  $("superAdminForm").classList.toggle("hidden", selectedMode !== "super");
}

async function seedFeaturesAndRoles(businessId) {
  await Promise.all(
    features.map(([id, name, description]) =>
      setDoc(doc(db, "features", id), { id, name, description }, { merge: true }),
    ),
  );

  const ownerPermissions = Object.fromEntries(features.map(([id]) => [id, true]));
  const cashierPermissions = Object.fromEntries(features.map(([id]) => [id, false]));
  cashierPermissions.dashboard = true;
  cashierPermissions.pos = true;

  await setDoc(
    doc(db, "roles", roleDocId(businessId, "super_admin")),
    {
      roleId: "super_admin",
      displayName: "Business Owner",
      businessId,
      permissions: ownerPermissions,
      isSystemRole: true,
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );

  await setDoc(
    doc(db, "roles", roleDocId(businessId, "cashier")),
    {
      roleId: "cashier",
      displayName: "Cashier",
      businessId,
      permissions: cashierPermissions,
      isSystemRole: true,
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );
}

async function registerSuperAdmin(event) {
  event.preventDefault();
  setMessage("Creating web super admin...");

  const setupSnap = await getDoc(doc(db, "system_config", "super_admin_setup"));
  const setup = setupSnap.data();
  const setupEnabled = setup?.enabled !== false;

  if (!setupSnap.exists() || !setupEnabled) {
    setMessage("Super admin setup is not enabled by system config.");
    return;
  }

  const name = $("superAdminName").value.trim();
  const email = $("superAdminEmail").value.trim();
  const password = $("superAdminPassword").value;

  state.bootstrappingSuperAdmin = true;

  try {
    let credential;
    try {
      credential = await createUserWithEmailAndPassword(auth, email, password);
    } catch (error) {
      if (error.code !== "auth/email-already-in-use") throw error;
      credential = await signInWithEmailAndPassword(auth, email, password);
    }

    const systemBusinessId = "system_admin";

    await seedFeaturesAndRoles(systemBusinessId);
    await setDoc(
      doc(db, "roles", roleDocId(systemBusinessId, "web_super_admin")),
      {
        roleId: "web_super_admin",
        displayName: "Web Super Admin",
        businessId: systemBusinessId,
        permissions: Object.fromEntries(features.map(([id]) => [id, true])),
        isSystemRole: true,
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );

    await setDoc(
      doc(db, "businesses", systemBusinessId),
      {
        id: systemBusinessId,
        name: "System Administration",
        ownerId: credential.user.uid,
        ownerEmail: email,
        isSystemBusiness: true,
        createdAt: serverTimestamp(),
      },
      { merge: true },
    );

    await setDoc(doc(db, "users", credential.user.uid), {
      id: credential.user.uid,
      name,
      email,
      role: "web_super_admin",
      businessId: systemBusinessId,
      branchId: null,
      isActive: true,
      isWebSuperAdmin: true,
      createdAt: serverTimestamp(),
    });

    await setDoc(
      doc(db, "system_config", "super_admin_setup"),
      {
        enabled: false,
        usedBy: credential.user.uid,
        usedAt: serverTimestamp(),
      },
      { merge: true },
    );

    const loaded = await loadCurrentUser(credential.user);
    state.appUser = loaded.appUser;
    state.businessId = loaded.businessId;
    state.business = loaded.business;
    await refresh();
    setMessage("");
  } catch (error) {
    setMessage(error.message);
  } finally {
    state.bootstrappingSuperAdmin = false;
  }
}

async function login(event) {
  event.preventDefault();
  setMessage("Signing in...");
  try {
    await signInWithEmailAndPassword(auth, $("loginEmail").value.trim(), $("loginPassword").value);
    setMessage("");
  } catch (error) {
    setMessage(error.message);
  }
}

async function loadCurrentUser(firebaseUser) {
  const userSnap = await getDoc(doc(db, "users", firebaseUser.uid));
  if (!userSnap.exists()) {
    throw new Error("User profile not found.");
  }
  const appUser = { id: firebaseUser.uid, ...userSnap.data() };
  const businessId = appUser.businessId || "default_business";
  const businessSnap = await getDoc(doc(db, "businesses", businessId));
  return {
    appUser,
    businessId,
    business: businessSnap.exists() ? businessSnap.data() : { name: "Business", id: businessId },
  };
}

async function loadBusinessData() {
  const businessId = state.businessId;
  const isWebSuperAdmin = state.appUser?.isWebSuperAdmin === true || state.appUser?.role === "web_super_admin";
  const [businessesSnap, branchesSnap, usersSnap, rolesSnap, productsSnap, salesSnap] = await Promise.all([
    isWebSuperAdmin
      ? getDocs(collection(db, "businesses"))
      : getDocs(query(collection(db, "businesses"), where("id", "==", businessId))),
    isWebSuperAdmin
      ? getDocs(collection(db, "branches"))
      : getDocs(query(collection(db, "branches"), where("businessId", "==", businessId))),
    isWebSuperAdmin
      ? getDocs(collection(db, "users"))
      : getDocs(query(collection(db, "users"), where("businessId", "==", businessId))),
    isWebSuperAdmin
      ? getDocs(collection(db, "roles"))
      : getDocs(query(collection(db, "roles"), where("businessId", "==", businessId))),
    isWebSuperAdmin
      ? getDocs(collection(db, "products"))
      : getDocs(query(collection(db, "products"), where("businessId", "==", businessId))),
    isWebSuperAdmin
      ? getDocs(query(collection(db, "sales"), limit(500)))
      : getDocs(query(collection(db, "sales"), where("businessId", "==", businessId), limit(200))),
  ]);

  state.businesses = businessesSnap.docs.map((item) => ({ id: item.id, ...item.data() }));
  state.branches = branchesSnap.docs.map((item) => ({ id: item.id, ...item.data() }));
  state.users = usersSnap.docs.map((item) => ({ id: item.id, ...item.data() }));
  state.roles = rolesSnap.docs.map((item) => ({ docId: item.id, ...item.data() }));
  state.products = productsSnap.docs.map((item) => ({ id: item.id, ...item.data() }));
  state.sales = salesSnap.docs.map((item) => ({ id: item.id, ...item.data() }));
}

function renderApp() {
  $("authView").classList.add("hidden");
  $("appView").classList.remove("hidden");
  $("businessLabel").textContent = state.business?.name || "Business";
  $("ownerLabel").textContent = `${state.appUser.name} • ${state.appUser.email}`;
  document.querySelectorAll(".nav").forEach((button) => {
    button.classList.toggle("active", button.dataset.page === state.page);
  });
  $("pageTitle").textContent = document.querySelector(`[data-page="${state.page}"]`)?.textContent || "Overview";
  document.querySelectorAll(".page").forEach((page) => page.classList.add("hidden"));
  $(`${state.page}Page`).classList.remove("hidden");

  renderOverview();
  renderBusinesses();
  renderBranches();
  renderUsers();
  renderRoles();
  renderProducts();
  renderSales();
}

function renderOverview() {
  const salesTotal = state.sales.reduce((sum, sale) => sum + Number(sale.totalAmount || 0), 0);
  const lowStock = state.products.filter((product) => Number(product.stockQuantity || 0) < 10).length;

  $("overviewPage").innerHTML = `
    <section class="grid metrics">
      ${metric("Businesses", state.businesses.filter((business) => !business.isSystemBusiness).length)}
      ${metric("Users", state.users.length)}
      ${metric("Locations", state.branches.length)}
      ${metric("Products", state.products.length)}
      ${metric("Low Stock", lowStock)}
      ${metric("Sales", state.sales.length)}
      ${metric("Revenue", money.format(salesTotal))}
    </section>
  `;
}

function metric(title, value) {
  return `<div class="card"><div class="small">${title}</div><div class="metric-value">${value}</div></div>`;
}

function renderBusinesses() {
  const isWebSuperAdmin = state.appUser?.isWebSuperAdmin === true || state.appUser?.role === "web_super_admin";
  if (!isWebSuperAdmin) {
    $("businessesPage").innerHTML = `<div class="card">Only web super admins can manage businesses.</div>`;
    return;
  }

  const businesses = state.businesses.filter((business) => !business.isSystemBusiness);
  $("businessesPage").innerHTML = `
    <div class="toolbar"><h2>Businesses</h2><button id="addBusinessOwner">Register business owner</button></div>
    ${table(["Business", "Owner", "Email", "Locations", "Users", "Actions"], businesses.map((business) => [
      business.name,
      ownerName(business.ownerId),
      business.ownerEmail || "-",
      state.branches.filter((branch) => branch.businessId === business.id).length,
      state.users.filter((user) => user.businessId === business.id).length,
      `<button class="secondary edit-business" data-id="${business.id}">Edit</button>`,
    ]))}
  `;
  $("addBusinessOwner").onclick = () => openBusinessOwnerModal();
  document.querySelectorAll(".edit-business").forEach((button) => {
    button.onclick = () => openBusinessOwnerModal(state.businesses.find((business) => business.id === button.dataset.id));
  });
}

function renderBranches() {
  $("branchesPage").innerHTML = `
    <div class="toolbar"><h2>Business Locations</h2><button id="addBranch">Add location</button></div>
    ${table(["Name", "Address", "Phone", "Actions"], state.branches.map((branch) => [
      branch.name,
      branch.address || "-",
      branch.phone || "-",
      actionButtons("branch", branch.id),
    ]))}
  `;
  $("addBranch").onclick = () => openBranchModal();
  bindActionButtons("branch", openBranchModal, async (branch) => deleteDoc(doc(db, "branches", branch.id)));
}

function renderUsers() {
  $("usersPage").innerHTML = `
    <div class="toolbar"><h2>Users</h2><button id="addUser">Add user</button></div>
    ${table(["Name", "Email", "Role", "Location", "Actions"], state.users.map((user) => [
      user.name,
      user.email,
      roleName(user.role),
      branchName(user.branchId),
      `<button class="secondary edit-user" data-id="${user.id}">Edit</button>`,
    ]))}
  `;
  $("addUser").onclick = () => openUserModal();
  document.querySelectorAll(".edit-user").forEach((button) => {
    button.onclick = () => openUserModal(state.users.find((user) => user.id === button.dataset.id));
  });
}

function renderRoles() {
  $("rolesPage").innerHTML = `
    <div class="toolbar"><h2>Roles & Features</h2><button id="addRole">Create role</button></div>
    ${table(["Role", "Enabled Features", "Actions"], state.roles.map((role) => [
      role.displayName,
      Object.entries(role.permissions || {}).filter(([, enabled]) => enabled).length,
      `<button class="secondary edit-role" data-id="${role.docId}">Edit</button> ${role.isSystemRole ? "" : `<button class="danger delete-role" data-id="${role.docId}">Delete</button>`}`,
    ]))}
  `;
  $("addRole").onclick = () => openRoleModal();
  document.querySelectorAll(".edit-role").forEach((button) => {
    button.onclick = () => openRoleModal(state.roles.find((role) => role.docId === button.dataset.id));
  });
  document.querySelectorAll(".delete-role").forEach((button) => {
    button.onclick = async () => {
      await deleteDoc(doc(db, "roles", button.dataset.id));
      await refresh();
    };
  });
}

function renderProducts() {
  $("productsPage").innerHTML = `
    <div class="toolbar"><h2>Products</h2></div>
    ${table(["Name", "Barcode", "Category", "Stock", "Price"], state.products.map((product) => [
      product.name,
      product.barcode || "-",
      product.category || "-",
      product.stockQuantity ?? 0,
      money.format(Number(product.price || 0)),
    ]))}
  `;
}

function renderSales() {
  $("salesPage").innerHTML = `
    <div class="toolbar"><h2>Sales</h2></div>
    ${table(["Date", "Payment", "Total", "Items"], state.sales.map((sale) => [
      formatDate(sale.timestamp),
      sale.paymentMethod || "-",
      money.format(Number(sale.totalAmount || 0)),
      saleItems(sale.itemsJson),
    ]))}
  `;
}

function table(headers, rows) {
  if (rows.length === 0) return `<div class="card">No data yet.</div>`;
  return `
    <table>
      <thead><tr>${headers.map((head) => `<th>${escapeHtml(head)}</th>`).join("")}</tr></thead>
      <tbody>${rows.map((row) => `<tr>${row.map((cell) => `<td>${cell}</td>`).join("")}</tr>`).join("")}</tbody>
    </table>
  `;
}

function actionButtons(type, id) {
  return `<div class="actions"><button class="secondary edit-${type}" data-id="${id}">Edit</button><button class="danger delete-${type}" data-id="${id}">Delete</button></div>`;
}

function bindActionButtons(type, editFn, deleteFn) {
  document.querySelectorAll(`.edit-${type}`).forEach((button) => {
    button.onclick = () => editFn(state[`${type}es`]?.find((item) => item.id === button.dataset.id) || state.branches.find((item) => item.id === button.dataset.id));
  });
  document.querySelectorAll(`.delete-${type}`).forEach((button) => {
    button.onclick = async () => {
      const item = state.branches.find((entry) => entry.id === button.dataset.id);
      await deleteFn(item);
      await refresh();
    };
  });
}

function openModal(title, bodyHtml, onSubmit) {
  $("modalTitle").textContent = title;
  $("modalBody").innerHTML = bodyHtml;
  $("modal").showModal();
  $("modalCancel").onclick = () => $("modal").close();
  $("modalForm").onsubmit = async (event) => {
    event.preventDefault();
    await onSubmit();
    $("modal").close();
    await refresh();
  };
}

function openBranchModal(branch = null) {
  openModal(
    branch ? "Edit location" : "Add location",
    `
      <label>Name<input id="modalName" value="${escapeAttr(branch?.name || "")}" required /></label>
      <label>Address<input id="modalAddress" value="${escapeAttr(branch?.address || "")}" /></label>
      <label>Phone<input id="modalPhone" value="${escapeAttr(branch?.phone || "")}" /></label>
    `,
    async () => {
      const ref = branch ? doc(db, "branches", branch.id) : doc(collection(db, "branches"));
      await setDoc(ref, {
        id: ref.id,
        businessId: state.businessId,
        name: $("modalName").value.trim(),
        address: $("modalAddress").value.trim(),
        phone: $("modalPhone").value.trim(),
        managerId: branch?.managerId || state.appUser.id,
        updatedAt: serverTimestamp(),
      }, { merge: true });
    },
  );
}

function openBusinessOwnerModal(business = null) {
  openModal(
    business ? "Edit business" : "Register business owner",
    business
      ? `
        <label>Business name<input id="modalBusinessName" value="${escapeAttr(business.name || "")}" required /></label>
        <label>Owner email<input id="modalOwnerEmail" value="${escapeAttr(business.ownerEmail || "")}" /></label>
      `
      : `
        <label>Owner name<input id="modalOwnerName" required /></label>
        <label>Business name<input id="modalBusinessName" required /></label>
        <label>Main location<input id="modalBranchName" value="Main Branch" required /></label>
        <label>Owner email<input id="modalOwnerEmail" type="email" required /></label>
        <label>Temporary password<input id="modalOwnerPassword" type="password" minlength="6" required /></label>
      `,
    async () => {
      if (business) {
        await updateDoc(doc(db, "businesses", business.id), {
          name: $("modalBusinessName").value.trim(),
          ownerEmail: $("modalOwnerEmail").value.trim(),
          updatedAt: serverTimestamp(),
        });
        return;
      }

      const ownerNameValue = $("modalOwnerName").value.trim();
      const businessNameValue = $("modalBusinessName").value.trim();
      const branchNameValue = $("modalBranchName").value.trim();
      const ownerEmailValue = $("modalOwnerEmail").value.trim();
      const ownerPasswordValue = $("modalOwnerPassword").value;
      const appName = `business_owner_${Date.now()}`;
      const secondary = initializeApp(firebaseConfig, appName);
      const secondaryAuth = getAuth(secondary);

      try {
        const credential = await createUserWithEmailAndPassword(
          secondaryAuth,
          ownerEmailValue,
          ownerPasswordValue,
        );
        const businessRef = doc(collection(db, "businesses"));
        const branchRef = doc(collection(db, "branches"));
        const businessId = businessRef.id;

        await setDoc(businessRef, {
          id: businessId,
          name: businessNameValue,
          ownerId: credential.user.uid,
          ownerEmail: ownerEmailValue,
          createdBy: state.appUser.id,
          createdAt: serverTimestamp(),
        });

        await seedFeaturesAndRoles(businessId);

        await setDoc(branchRef, {
          id: branchRef.id,
          businessId,
          name: branchNameValue,
          address: "",
          phone: "",
          managerId: credential.user.uid,
          createdAt: serverTimestamp(),
        });

        await setDoc(doc(db, "users", credential.user.uid), {
          id: credential.user.uid,
          name: ownerNameValue,
          email: ownerEmailValue,
          role: "super_admin",
          branchId: branchRef.id,
          businessId,
          isActive: true,
          createdAt: serverTimestamp(),
        });

        await signOut(secondaryAuth);
      } finally {
        await deleteApp(secondary);
      }
    },
  );
}

function openUserModal(user = null) {
  openModal(
    user ? "Edit user" : "Add user",
    `
      ${user ? "" : `<label>Name<input id="modalName" required /></label><label>Email<input id="modalEmail" type="email" required /></label><label>Temporary password<input id="modalPassword" type="password" minlength="6" required /></label>`}
      <label>Role<select id="modalRole">${state.roles.map((role) => `<option value="${role.roleId}" ${role.roleId === user?.role ? "selected" : ""}>${escapeHtml(role.displayName)}</option>`).join("")}</select></label>
      <label>Location<select id="modalBranch"><option value="">All locations</option>${state.branches.map((branch) => `<option value="${branch.id}" ${branch.id === user?.branchId ? "selected" : ""}>${escapeHtml(branch.name)}</option>`).join("")}</select></label>
    `,
    async () => {
      if (user) {
        await updateDoc(doc(db, "users", user.id), {
          role: $("modalRole").value,
          branchId: $("modalBranch").value || null,
          businessId: state.businessId,
          updatedAt: serverTimestamp(),
        });
        return;
      }

      const appName = `staff_${Date.now()}`;
      const secondary = initializeApp(firebaseConfig, appName);
      const secondaryAuth = getAuth(secondary);
      try {
        const credential = await createUserWithEmailAndPassword(secondaryAuth, $("modalEmail").value.trim(), $("modalPassword").value);
        await setDoc(doc(db, "users", credential.user.uid), {
          id: credential.user.uid,
          name: $("modalName").value.trim(),
          email: $("modalEmail").value.trim(),
          role: $("modalRole").value,
          branchId: $("modalBranch").value || null,
          businessId: state.businessId,
          isActive: true,
          createdAt: serverTimestamp(),
        });
        await signOut(secondaryAuth);
      } finally {
        await deleteApp(secondary);
      }
    },
  );
}

function openRoleModal(role = null) {
  const permissions = role?.permissions || {};
  openModal(
    role ? "Edit role" : "Create role",
    `
      <label>Role name<input id="modalRoleName" value="${escapeAttr(role?.displayName || "")}" required /></label>
      <div class="switch-row">
        ${features.map(([id, name, description]) => `
          <label>
            <span><strong>${escapeHtml(name)}</strong><br><small>${escapeHtml(description)}</small></span>
            <input type="checkbox" data-feature="${id}" ${permissions[id] ? "checked" : ""} />
          </label>
        `).join("")}
      </div>
    `,
    async () => {
      const displayName = $("modalRoleName").value.trim();
      const roleId = role?.roleId || slug(displayName);
      const docId = role?.docId || roleDocId(state.businessId, roleId);
      const nextPermissions = {};
      document.querySelectorAll("[data-feature]").forEach((input) => {
        nextPermissions[input.dataset.feature] = input.checked;
      });
      await setDoc(doc(db, "roles", docId), {
        roleId,
        displayName,
        businessId: state.businessId,
        permissions: nextPermissions,
        isSystemRole: role?.isSystemRole || false,
        updatedAt: serverTimestamp(),
      }, { merge: true });
    },
  );
}

function roleName(roleId) {
  return state.roles.find((role) => role.roleId === roleId)?.displayName || roleId || "-";
}

function ownerName(ownerId) {
  return state.users.find((user) => user.id === ownerId)?.name || "-";
}

function branchName(branchId) {
  return state.branches.find((branch) => branch.id === branchId)?.name || "All locations";
}

function formatDate(value) {
  const date = typeof value === "string" ? new Date(value) : value?.toDate?.();
  return date && !Number.isNaN(date.getTime()) ? date.toLocaleString() : "-";
}

function saleItems(value) {
  try {
    const items = JSON.parse(value || "[]");
    return items.map((item) => `${item.quantity || 1}x ${escapeHtml(item.name || "Item")}`).join(", ");
  } catch (_) {
    return "-";
  }
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#039;",
  })[char]);
}

function escapeAttr(value) {
  return escapeHtml(value).replace(/`/g, "&#096;");
}

async function refresh() {
  await loadBusinessData();
  renderApp();
}

$("loginTab").onclick = () => showAuth("login");
$("superAdminTab").onclick = () => showAuth("super");
$("loginForm").onsubmit = login;
$("superAdminForm").onsubmit = registerSuperAdmin;
$("logoutButton").onclick = () => signOut(auth);
$("refreshButton").onclick = refresh;
document.querySelectorAll(".nav").forEach((button) => {
  button.onclick = () => {
    state.page = button.dataset.page;
    renderApp();
  };
});

onAuthStateChanged(auth, async (firebaseUser) => {
  state.firebaseUser = firebaseUser;

  if (!firebaseUser) {
    $("appView").classList.add("hidden");
    $("authView").classList.remove("hidden");
    return;
  }

  try {
    const loaded = await loadCurrentUser(firebaseUser);
    state.appUser = loaded.appUser;
    state.businessId = loaded.businessId;
    state.business = loaded.business;
    await seedFeaturesAndRoles(state.businessId);
    await refresh();
  } catch (error) {
    if (state.bootstrappingSuperAdmin) return;
    await signOut(auth);
    $("appView").classList.add("hidden");
    $("authView").classList.remove("hidden");
    setMessage(error.message);
  }
});
