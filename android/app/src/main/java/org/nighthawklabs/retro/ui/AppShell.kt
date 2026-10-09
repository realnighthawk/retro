package org.nighthawklabs.retro.ui

import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checkroom
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import android.net.ConnectivityManager
import android.net.Network
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.material3.TextButton
import kotlinx.coroutines.launch
import org.nighthawklabs.retro.data.WardrobeWrites
import org.nighthawklabs.retro.data.WardrobePhotos
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.navigation
import androidx.navigation.compose.rememberNavController
import org.nighthawklabs.retro.DevMode
import org.nighthawklabs.retro.auth.Auth
import org.nighthawklabs.retro.auth.AuthState
import org.nighthawklabs.retro.data.WardrobeReadCache
import org.nighthawklabs.retro.data.WardrobeStore
import org.nighthawklabs.retro.net.Engine
import org.nighthawklabs.retro.ui.theme.Retro

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppShell(userId: String, onOpenAccount: () -> Unit) {
    val context = LocalContext.current.applicationContext
    val scope = rememberCoroutineScope()
    var pending by remember { mutableStateOf(false) }
    val store = remember(userId) {
        val currentUser = { (Auth.state.value as? AuthState.SignedIn)?.userId }
        val engine = Engine.live(userId, currentUser)
        val writes = WardrobeWrites.live(context.noBackupFilesDir, engine) { currentUser() == userId }
        WardrobeStore(engine, WardrobeReadCache(context.cacheDir, userId, engine.cacheScope),
            writes = writes,
            photos = WardrobePhotos.live(context.noBackupFilesDir, context.cacheDir, engine, writes),
            drafts = WardrobeSavedDrafts.live(context.noBackupFilesDir, engine),
            stillOwner = { currentUser() == userId },
        ).also { store -> store.onEnqueued = { scope.launch { store.sync() } } }
    }
    LaunchedEffect(userId) { store.sync() }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(store, lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) store.photos?.foreground = false
            if (event == Lifecycle.Event.ON_START) store.photos?.foreground = true
            if (event == Lifecycle.Event.ON_RESUME) scope.launch { store.sync() }
        }
        lifecycle.addObserver(observer)
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { scope.launch { store.sync() } }
        }
        connectivity.registerDefaultNetworkCallback(callback)
        onDispose { lifecycle.removeObserver(observer); connectivity.unregisterNetworkCallback(callback) }
    }
    if (pending) WardrobePendingScreen(store) { pending = false }
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val tabs = listOf("today", "wardrobe", "history")
    val selected = tabs.firstOrNull { tab -> entry?.destination?.hierarchy?.any { it.route == tab } == true } ?: "today"
    val start = remember { DevMode.surface?.lowercase()?.takeIf { it in tabs } ?: "today" }
    val tok = Retro.tok

    Scaffold(
        containerColor = tok.bone,
        topBar = {
            TopAppBar(
                title = { Text(selected.replaceFirstChar { it.titlecase() }) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = tok.bone),
                actions = {
                    TextButton(onClick = { pending = true }) { Text("Pending ${(store.writes?.items?.size ?: 0) + (store.photos?.batches?.size ?: 0) + (store.drafts?.items?.size ?: 0) + (store.photos?.drafts?.size ?: 0)}") }
                    IconButton(onClick = onOpenAccount) { Icon(Icons.Filled.Person, contentDescription = "Account") }
                },
            )
        },
        bottomBar = {
            NavigationBar(containerColor = tok.paper) {
                tabs.forEach { tab ->
                    NavigationBarItem(
                        selected = selected == tab,
                        onClick = {
                            nav.navigate(tab) {
                                popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = {
                            val icon = when (tab) {
                                "wardrobe" -> Icons.Filled.Checkroom
                                "history" -> Icons.Filled.History
                                else -> Icons.Filled.WbSunny
                            }
                            Icon(icon, contentDescription = null, modifier = Modifier.size(22.dp))
                        },
                        label = { Text(tab.replaceFirstChar { it.titlecase() }) },
                    )
                }
            }
        },
    ) { padding ->
        NavHost(navController = nav, startDestination = start, modifier = Modifier.padding(padding)) {
            tabs.forEach { tab ->
                navigation(startDestination = "$tab/list", route = tab) {
                    composable("$tab/list") {
                        when (tab) {
                            "today" -> WardrobeTodayScreen(store) { nav.navigate("$tab/outfit/$it") }
                            "wardrobe" -> WardrobeInventoryScreen(store) { nav.navigate("$tab/garment/$it") }
                            "history" -> WardrobeHistoryScreen(store) { nav.navigate("$tab/outfit/$it") }
                        }
                    }
                    if (tab == "wardrobe") {
                        composable("$tab/garment/{id}") { destination ->
                            WardrobeGarmentScreen(store, destination.arguments?.getString("id") ?: return@composable) { nav.popBackStack() }
                        }
                    } else {
                        composable("$tab/outfit/{id}") { destination ->
                            WardrobeOutfitScreen(store, destination.arguments?.getString("id") ?: return@composable) { nav.popBackStack() }
                        }
                    }
                }
            }
        }
    }
}
